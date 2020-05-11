#!/usr/bin/python
import argparse
import codecs
from enum import Enum
import filecmp
import glob
import hashlib
import os.path
import re
import sqlite3
import subprocess
import sys
import time
import uuid

VERBOSE = False
NO_COMMIT = False
REMOTE_MMS_PARTS_DIR = "/home/nemo/.local/share/commhistory/data"
LOCAL_UID = "/org/freedesktop/Telepathy/Account/ring/tel/ril_0"

usage = """Export/Import SMS, call log, and MMS from commhistory database
Usage:
  {appName} export-from-db-sms DB_FILE CSV_FILE [OPTS]
    export SMS messages from DB_FILE to CSV_FILE

  {appName} export-from-db-calls DB_FILE CSV_FILE [OPTS]
    export call log entries from DB_FILE to CSV_FILE

  {appName} export-from-db-mms DB_FILE MMS_MSG_DIR MMS_PARTS_DIR [OPTS]
    export MMS messages from DB_FILE to MMS_MSG_DIR, using att files in MMS_PARTS_DIR

  {appName} import-to-db-sms DB_FILE CSV_FILE [OPTS]
    insert SMS from CSV_FILE into DB_FILE

  {appName} import-to-db-calls DB_FILE CSV_FILE [OPTS]
    insert call log entries from CSV_FILE into DB_FILE

  {appName} import-to-db-mms DB_FILE MMS_MSG_DIR MMS_PARTS_DIR [OPTS]
    insert MMS from MMS_MSG_DIR into DB_FILE, and ensure att files in MMS_PARTS_DIR

  {appName} mms-hash SUBJECT BODY [ATT_FILE ATT_FILE ..]
    insert MMS from MMS_MSG_DIR into DB_FILE, and ensure att files in MMS_PARTS_DIR

  OPTS:
    --my-number       default phone number for "from" in OUT-MMS and "to" in INC-MMS
    --limit           only import LIMIT entries into DB_FILE
    --verbose         verbose output (slower)
    --no-commit       do not commit changes when inserting into DB_FILE
""".format(appName=os.path.basename(__file__))

SMS_DIR = Enum('SMS_DIR', ['OUT', 'INC'])
MMS_DIR = Enum('MMS_DIR', ['OUT', 'INC', 'NTF'])
CALL_DIR = Enum('CALL_DIR', ['OUT', 'INC', 'MIS', 'REJ'])

MMS_ATT_FILENAME_PREFIX_REGEX = re.compile(''
   + r'^\d+_'
   + r'([0-9+]+-)*[0-9+]+_'
   + r'(' + '|'.join(sorted(MMS_DIR.__members__.keys())) + r')_'
   + r'[0-9a-f]{32}_'
   )

def addSubparser(subparsers, cmd, args):
  p = subparsers.add_parser(cmd)
  for arg in args:
    p.add_argument(arg)
  addOptArgs(p)
  return p

def addOptArgs(parser):
  parser.add_argument('--my-number',),
  parser.add_argument('--verbose', '-v', action='store_true')
  parser.add_argument('--no-commit', '-n', action='store_true')
  parser.add_argument('--limit', type=int, default=0)

class MyArgumentParser(argparse.ArgumentParser):
  def error(self, message):
    print(usage + "\nERROR: " + message)
    quit(1)

def main():
  parser = MyArgumentParser(add_help=False)
  addOptArgs(parser)
  subparsers = parser.add_subparsers(dest='COMMAND')
  addSubparser(subparsers, 'export-from-db-sms', ['DB_FILE', 'CSV_FILE'])
  addSubparser(subparsers, 'export-from-db-calls', ['DB_FILE', 'CSV_FILE'])
  addSubparser(subparsers, 'export-from-db-mms', ['DB_FILE', 'MMS_MSG_DIR', 'MMS_PARTS_DIR'])
  addSubparser(subparsers, 'import-to-db-sms', ['DB_FILE', 'CSV_FILE'])
  addSubparser(subparsers, 'import-to-db-calls', ['DB_FILE', 'CSV_FILE'])
  addSubparser(subparsers, 'import-to-db-mms', ['DB_FILE', 'MMS_MSG_DIR', 'MMS_PARTS_DIR'])
  mmsHashSubParser = addSubparser(subparsers, 'mms-hash', ['SUBJECT', 'BODY'])
  mmsHashSubParser.add_argument('ATT_FILE', nargs='*')
  args = parser.parse_args()

  global VERBOSE, NO_COMMIT, MY_NUMBER
  VERBOSE = args.verbose
  NO_COMMIT = args.no_commit
  MY_NUMBER = args.my_number

  if args.COMMAND == "mms-hash":
    subject = args.SUBJECT
    body = args.BODY
    attFileList = args.ATT_FILE
    attFiles = {}
    for attFile in attFileList:
      if not os.path.isfile(attFile):
        print("ERROR: ATT_FILE '" + attFile + "' does not exist")
        quit(1)
      attName = os.path.basename(attFile)
      attFiles[attName] = attFile
    checksum = generateMMSChecksum(subject, body, attFiles)
    print(checksum)
    quit(0)

  if not os.path.isfile(args.DB_FILE):
    print("ERROR: commhistory db file " + args.DB_FILE + " does not exist")
    quit(1)

  if args.COMMAND == "export-from-db-sms":
    texts = readTextsFromCommHistory(args.DB_FILE)
    print("read " + str(len(texts)) + " SMS messages from " + args.DB_FILE)
    f = codecs.open(args.CSV_FILE, 'w', 'utf-8')
    for txt in texts:
      f.write(txt.toCsv() + "\n")
    f.close()
  elif args.COMMAND == "export-from-db-calls":
    calls = readCallsFromCommHistory(args.DB_FILE)
    print("read " + str(len(calls)) + " calls from " + args.DB_FILE)
    f = codecs.open(args.CSV_FILE, 'w', 'utf-8')
    for call in calls:
      f.write(call.toCsv() + "\n")
    f.close()
  elif args.COMMAND == "export-from-db-mms":
    if not os.path.isdir(args.MMS_MSG_DIR):
      print("ERROR: no <MMS_MSG_DIR> for writing to")
      quit(1)
    elif not os.path.isdir(args.MMS_PARTS_DIR):
      print("ERROR: no <MMS_PARTS_DIR> to read attachments from")
      quit(1)
    mmsMessages = readMMSFromCommHistory(args.DB_FILE, args.MMS_PARTS_DIR)
    print("read " + str(len(mmsMessages)) + " MMS messages from " + args.DB_FILE)
    attFileCount = 0
    for msg in mmsMessages:
      dirName = msg.getMsgDirName()
      msgDir = args.MMS_MSG_DIR + "/" + dirName
      if not os.path.isdir(msgDir):
        os.mkdir(msgDir)
      infoFilePath = msgDir + "/" + "info"
      infoFile = codecs.open(infoFilePath, 'w', 'utf-8')
      infoFile.write(msg.getInfo())
      infoFile.close()
      os.system("touch '" + infoFilePath + "' -r '" + msgDir + "'")
      for attName in sorted(msg.attFiles.keys()):
        srcFile = msg.attFiles[attName]
        destFile = msgDir + "/" + attName
        if 0 != os.system("cp -ar --reflink '" + srcFile + "' '" + destFile + "'"):
          print("failed to copy " + str(srcFile))
          quit(1)
        attFileCount += 1
    print("copied " + str(attFileCount) + " files from " + args.MMS_PARTS_DIR)
  elif args.COMMAND == "import-to-db-sms":
    print("Reading texts from CSV file:")
    starttime = time.time()
    texts = readTextsFromCSV(args.CSV_FILE)
    print("finished in {0} seconds, {1} texts read".format( (time.time()-starttime), len(texts) ))

    ignoredMissingNumberCount = 0
    ignoredMMSToSMSCount = 0
    okMessages = []
    for txt in texts:
      if txt.number == None or len(txt.number) == 0:
        ignoredMissingNumberCount += 1
      elif txt.sms_mms_type == "M":
        ignoredMMSToSMSCount += 1
      else:
        okMessages.append(txt)
    texts = okMessages

    print("ignoring:")
    print(" %5d SMS missing number" % ignoredMissingNumberCount)
    print(" %5d MMS-to-SMS messages\n" % ignoredMMSToSMSCount)

    print("sorting all {0} texts by date".format(len(texts)))
    texts = sorted(texts, key=lambda text: text.date_millis)

    if args.limit > 0:
      print("saving only the last {0} texts".format(args.limit))
      texts = texts[ (-args.limit) : ]

    print("Saving SMS into commhistory db:" + str(args.DB_FILE))
    importSMSToDb(texts, args.DB_FILE)
  elif args.COMMAND == "import-to-db-calls":
    print("Reading calls from CSV file:")
    starttime = time.time()
    calls = readCallsFromCSV(args.CSV_FILE)
    print("finished in {0} seconds, {1} calls read".format( (time.time()-starttime), len(calls) ))

    print("sorting all {0} calls by date".format(len(calls)))
    calls = sorted(calls, key=lambda call: call.date_millis)

    if args.limit > 0:
      print("saving only the last {0} calls".format(args.limit))
      calls = calls[ (-args.limit) : ]

    print("Saving calls into commhistory db:" + str(args.DB_FILE))
    importCallsToDb(calls, args.DB_FILE)
  elif args.COMMAND == "import-to-db-mms":
    if not os.path.isdir(args.MMS_MSG_DIR):
      print("invalid MMS_MSG_DIR: " + args.MMS_MSG_DIR)
      quit(1)
    elif not os.path.isdir(args.MMS_PARTS_DIR):
      print("invalid MMS_PARTS_DIR: " + args.MMS_PARTS_DIR)
      quit(1)
    print("reading mms from " + args.MMS_MSG_DIR)
    mmsMessages = readMMSFromMsgDir(args.MMS_MSG_DIR, args.MMS_PARTS_DIR)

    ignoredNTFCount = 0
    ignoredGroupCount = 0
    ignoredMissingToCount = 0
    ignoredMissingFromCount = 0
    okMessages = []
    for mms in mmsMessages:
      if mms.direction == MMS_DIR.NTF:
        ignoredNTFCount += 1
      elif len(mms.to_numbers) > 1:
        ignoredGroupCount += 1
      elif len(mms.to_numbers) < 1:
        ignoredMissingToCount += 1
      elif mms.from_number == None or mms.from_number == "":
        ignoredMissingFromCount += 1
      else:
        okMessages.append(mms)
    mmsMessages = okMessages

    print("ignoring:")
    print(" %5d NTF MMS" % ignoredNTFCount)
    print(" %5d group MMS (unsupported on sailfish)" % ignoredGroupCount)
    print(" %5d MMS missing 'to' number\n" % ignoredMissingToCount)
    print(" %5d MMS missing 'from' number\n" % ignoredMissingFromCount)

    print("sorting all {0} MMS messages by date".format(len(mmsMessages)))
    mmsMessages = sorted(mmsMessages, key=lambda mms: mms.date_millis)

    if args.limit > 0:
      print("saving only the last {0} MMS messages".format(args.limit))
      mmsMessages = mmsMessages[ (-args.limit) : ]

    print("checking MMS message consistency\n")
    for mms in mmsMessages:
      dirName = mms.getMsgDirName()
      msgDir = args.MMS_MSG_DIR + "/" + dirName
      if not os.path.isdir(msgDir):
        print("error reading MMS(" + str(msgDir) + ":\n" + str(mms))
        quit(1)

      oldChecksum = mms.checksum
      mms.generateChecksum()
      newChecksum = mms.checksum

      if oldChecksum != newChecksum:
        print("mismatched checksum for MMS message\n" + str(mms))
        quit(1)

    print("getting sha256 checksums of all att files in parts dir")
    partsDirFilesBySHA256ByFilename = {}
    for root, dirnames, filenames in os.walk(args.MMS_PARTS_DIR):
      if ".git" not in root:
        for filename in filenames:
          f = os.path.join(root, filename)
          sha256 = hashlib.sha256(open(f, 'rb').read()).hexdigest()
          if sha256 not in partsDirFilesBySHA256ByFilename:
            partsDirFilesBySHA256ByFilename[sha256] = {}
          unprefixedFilename = MMS_ATT_FILENAME_PREFIX_REGEX.sub('', filename)
          partsDirFilesBySHA256ByFilename[sha256][unprefixedFilename] = f

    print("matching up att files from msg dir against parts dir by checksum")
    for mms in mmsMessages:
      for filename in sorted(list(mms.attFiles.keys())):
        srcFile = mms.attFiles[filename]
        sha256 = hashlib.sha256(open(srcFile, 'rb').read()).hexdigest()

        if sha256 not in partsDirFilesBySHA256ByFilename:
          print("ERROR: att missing from parts dir for mms\n" + str(mms))
          quit(1)
        sha256Files = partsDirFilesBySHA256ByFilename[sha256]
        if filename not in sha256Files:
          print("ERROR: att missing from parts dir for mms\n" + str(mms))
          quit(1)

        destFile = sha256Files[filename]
        remoteFile = re.sub('^' + args.MMS_PARTS_DIR + '/?', REMOTE_MMS_PARTS_DIR + '/', destFile)

        mms.attFiles[filename] = destFile
        mms.attFilesRemotePaths[filename] = remoteFile
    print("read " + str(len(mmsMessages)) + " MMS messages")

    print("Saving MMS into commhistory db:" + str(args.DB_FILE))
    importMMSToDb(mmsMessages, args.DB_FILE)
  else:
    print("invalid <COMMAND>: " + args.COMMAND)
    quit(1)

def generateMMSChecksum(subject, body, attFiles):
  md5 = hashlib.md5()
  if subject != None:
    md5.update(escapeStr(subject.encode("utf-8")))
  if body != None:
    md5.update(escapeStr(body.encode("utf-8")))
  for attName in sorted(attFiles.keys()):
    md5.update("\n" + attName + "\n")
    filepath = attFiles[attName]
    if not os.path.isfile(filepath):
      print("missing att file: " + filepath)
      quit(1)
    f = open(filepath, 'r')
    md5.update(f.read())
    f.close()
  return md5.hexdigest()

class Text:
  def __init__(self, number, date_millis, date_sent_millis,
               sms_mms_type, direction, date_format, body):
    self.number = number
    self.date_millis = date_millis
    self.date_sent_millis = date_sent_millis
    self.sms_mms_type = sms_mms_type
    self.direction = direction
    self.date_format = date_format
    self.body = body
  def cleanNumber(self):
    self.number = cleanNumber(self.number)
  def toCsv(self):
    date_sent_millis = self.date_sent_millis
    if date_sent_millis == 0:
      date_sent_millis = self.date_millis
    return (""
      + ""  + cleanNumber(self.number)
      + "," + str(self.date_millis)
      + "," + str(date_sent_millis)
      + "," + self.sms_mms_type
      + "," + self.getDirectionStr()
      + "," + self.date_format
      + "," + "\"" + escapeStr(self.body) + "\""
    )
  def isOutgoing(self):
    return self.isDirection(SMS_DIR.OUT)
  def isIncoming(self):
    return self.isDirection(SMS_DIR.INC)
  def isDirection(self, smsDir):
    self.assertDirectionValid()
    return self.direction == smsDir
  def getDirectionStr(self):
    self.assertDirectionValid()
    return self.direction.name
  def assertDirectionValid(self):
    if self.direction not in SMS_DIR:
      print("invalid SMS direction: " + str(self.direction))
      quit(1)
  def __unicode__(self):
    return self.toCsv()
  def __str__(self):
    return unicode(self).encode('utf-8')

class Call:
  def __init__(self, number, date_millis, direction, date_format, duration_format):
    self.number = number
    self.date_millis = date_millis
    self.direction = direction
    self.date_format = date_format
    self.duration_format = duration_format
  def cleanNumber(self):
    self.number = cleanNumber(self.number)
  def getDurationSex(self):
    durationRegex = re.compile(r'\s*(-?)\s*(\d+)h\s*(\d+)m\s*(\d+)s')
    m = durationRegex.match(self.duration_format)
    if not m or len(m.groups()) != 4:
      print("invalid duration format: " + self.duration_format)
      quit(1)
    durNeg = m.group(1)
    durHrs = int(m.group(2))
    durMin = int(m.group(3))
    durSec = int(m.group(4))
    durationSex = durHrs * 60 * 60 + durMin * 60 + durSec
    if "-" in durNeg:
      durationSex = 0 - durationSex
    return durationSex
  def toCsv(self):
    return (""
      + ""  + cleanNumber(self.number)
      + "," + str(self.date_millis)
      + "," + self.getDirectionStr()
      + "," + self.date_format
      + "," + self.duration_format
    )
  def isOutgoing(self):
    return self.isDirection(CALL_DIR.OUT)
  def isIncoming(self):
    return self.isDirection(CALL_DIR.INC)
  def isDirection(self, callDir):
    self.assertDirectionValid()
    return self.direction == callDir
  def getDirectionStr(self):
    self.assertDirectionValid()
    return self.direction.name
  def assertDirectionValid(self):
    if self.direction not in CALL_DIR:
      print("invalid CALL direction: " + str(self.direction))
      quit(1)
  def __unicode__(self):
    return self.toCsv()
  def __str__(self):
    return unicode(self).encode('utf-8')

def escapeStr(s):
  return (s
    .replace('&', '&amp;')
    .replace('\\', '&backslash;')
    .replace('\n', '\\n')
    .replace('\r', '\\r')
    .replace('"', '\\"')
    .replace('&backslash;', '\\\\')
    .replace('&amp;', '&')
  )

def unescapeStr(s):
  return (s
    .replace('&', '&amp;')
    .replace('\\\\', '&backslash;')
    .replace('\\n', '\n')
    .replace('\\r', '\r')
    .replace('\\"', '"')
    .replace('&backslash;', '\\')
    .replace('&amp;', '&')
  )

class MMS:
  def __init__(self, mms_parts_dir):
    self.mms_parts_dir = mms_parts_dir
    self.from_number = None
    self.to_numbers = []
    self.date_millis = None
    self.date_sent_millis = None
    self.direction = None
    self.date_format = None
    self.subject = None
    self.body = None

    self.parts = []
    self.attFiles = {}
    self.attFilesRemotePaths = {}
    self.checksum = None
  def cleanNumbers(self):
    self.from_number = cleanNumber(self.from_number)
    toNumbers = []
    for toNumber in self.to_numbers:
      toNumbers.append(cleanNumber(toNumber))
    self.to_numbers = toNumbers
  def parseParts(self):
    self.attFiles = {}
    self.attFilesRemotePaths = {}
    self.checksum = None
    for p in self.parts:
      if 'smil' in p.part_type:
        pass
      elif p.filepath != None:
        relFilepath = p.filepath
        relFilepath = re.sub('^' + REMOTE_MMS_PARTS_DIR + '/', '', relFilepath)
        filename = relFilepath
        filename = re.sub('^\d+/', '', filename)
        filename = re.sub('^msg-\d+-\d+/', '', filename)
        if "/" in filename:
          print("filename contains path sep '/': " + filename)
          quit(1)
        unprefixedFilename = MMS_ATT_FILENAME_PREFIX_REGEX.sub('', filename)
        attName = unprefixedFilename
        localFilepath = self.mms_parts_dir + "/" + relFilepath
        self.attFiles[attName] = localFilepath
        self.attFilesRemotePaths[attName] = p.filepath
      else:
        print("invalid MMS part: " + str(p))
        quit(1)
    self.checksum = self.generateChecksum()
  def generateChecksum(self):
    return generateMMSChecksum(self.subject, self.body, self.attFiles)
  def getMsgDirName(self):
    dirName = ""
    dirName += str(self.date_millis)
    dirName += "_"
    if self.isOutgoing():
      dirName += "-".join(self.to_numbers)
    elif self.isIncoming():
      dirName += str(self.from_number)
    dirName += "_"
    dirName += self.getDirectionStr()
    dirName += "_"
    dirName += str(self.checksum)
    return dirName
  def getInfo(self):
    date_sent_millis = self.date_sent_millis
    if date_sent_millis == 0:
      date_sent_millis = self.date_millis
    info = ""
    info += "from=" + str(self.from_number) + "\n"
    for to_number in self.to_numbers:
      info += "to=" + str(to_number) + "\n"
    info += "dir=" + self.getDirectionStr() + "\n"
    info += "date=" + str(self.date_millis) + "\n"
    info += "date_sent=" + str(date_sent_millis) + "\n"
    info += "subject=\"" + escapeStr(self.subject) + "\"\n"
    info += "body=\"" + escapeStr(self.body) + "\"\n"
    for attName in sorted(self.attFiles.keys()):
      info += "att=" + str(attName) + "\n"
    info += "checksum=" + str(self.checksum) + "\n"
    return info
  def isOutgoing(self):
    return self.isDirection(MMS_DIR.OUT)
  def isIncoming(self):
    return self.isDirection(MMS_DIR.INC) or self.isDirection(MMS_DIR.NTF)
  def isDirection(self, mmsDir):
    self.assertDirectionValid()
    return self.direction == mmsDir
  def getDirectionStr(self):
    self.assertDirectionValid()
    return self.direction.name
  def assertDirectionValid(self):
    if self.direction not in MMS_DIR:
      print("invalid MMS direction: " + str(self.direction))
      quit(1)
  def __unicode__(self):
    return self.getInfo()
  def __str__(self):
    return unicode(self).encode('utf-8')

class MMSPart:
  def __init__(self):
    self.part_type = None
    self.filepath = None

def cleanNumber(number):
  if number == None:
    number = ''
  number = re.sub(r'[^+0-9]', '', number)
  number = re.sub(r'^\+?1(\d{10})$', '\\1', number)
  return number

def readTextsFromCSV(csvFile):
  try:
    csvFile = open(csvFile, 'r')
    csvContents = csvFile.read()
    csvFile.close()
  except IOError:
    print("could not read csv file: " + str(csvFile))
    quit(1)

  texts = []
  rowRegex = re.compile(''
    + r'([0-9+]*),'
    + r'(\d+),'
    + r'(\d+),'
    + r'(S|M),'
    + r'(' + '|'.join(sorted(SMS_DIR.__members__.keys())) + r'),'
    + r'([^,]*),'
    + r'\"(.*)\"'
    )
  for row in csvContents.splitlines():
    m = rowRegex.match(row)
    if not m or len(m.groups()) != 7:
      print("invalid SMS CSV line: " + row)
      quit(1)
    number           = m.group(1)
    date_millis      = int(m.group(2))
    date_sent_millis = int(m.group(3))
    sms_mms_type     = m.group(4)
    directionStr     = m.group(5)
    date_format      = m.group(6)
    body             = unescapeStr(m.group(7)).decode('utf-8')

    texts.append(Text( number
                     , date_millis
                     , date_sent_millis
                     , sms_mms_type
                     , SMS_DIR.__members__[directionStr]
                     , date_format
                     , body
                     ))
  return texts

def readTextsFromCommHistory(db_file):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()
  i=0
  texts = []
  query = c.execute(
    'SELECT remoteUid, startTime, endTime, direction, freeText \
     FROM events \
     WHERE type = 2 \
     ORDER BY id ASC;')
  for row in query:
    number = row[0]
    date_start_millis = long(row[1]) * 1000
    date_end_millis = long(row[2]) * 1000
    dir_type = row[3]
    body = row[4]

    if dir_type == 2:
      direction = SMS_DIR.OUT
    elif dir_type == 1:
      direction = SMS_DIR.INC
    else:
      print("INVALID SMS DIRECTION TYPE: " + str(dir_type) + "\n" + str(row))
      quit(1)

    sms_mms_type = "S"
    date_millis = date_end_millis
    date_sent_millis = date_start_millis

    date_format = time.strftime("%Y-%m-%d %H:%M:%S",
      time.localtime(date_millis/1000))

    txt = Text(number, date_millis, date_sent_millis,
      sms_mms_type, direction, date_format, body)
    texts.append(txt)
    if VERBOSE:
      print(str(txt))
  return texts

def readCallsFromCommHistory(db_file):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()
  i=0
  calls = []
  query = c.execute(
    'SELECT remoteUid, startTime, endTime, direction, isMissedCall, headers \
     FROM events \
     WHERE type = 3 \
     ORDER BY id ASC;')
  for row in query:
    number = row[0]
    date_start_millis = long(row[1]) * 1000
    date_end_millis = long(row[2]) * 1000
    dir_type = row[3]
    is_missed_call = row[4]
    headersRejectedHack = row[5]

    if headersRejectedHack != None and "rejected" in headersRejectedHack:
      direction = CALL_DIR.REJ
    elif int(is_missed_call) == 1:
      direction = CALL_DIR.MIS
    elif dir_type == 2:
      direction = CALL_DIR.OUT
    elif dir_type == 1:
      direction = CALL_DIR.INC
    else:
      print("INVALID CALL DIRECTION TYPE: " + str(dir_type) + "\n" + str(row))
      quit(1)

    date_millis = date_start_millis
    durationSex = long((date_end_millis - date_start_millis)/1000)

    date_format = time.strftime("%Y-%m-%d %H:%M:%S",
      time.localtime(date_millis/1000))

    if durationSex < 0:
      durSign = "-"
      durationSex = 0 - durationSex
    else:
      durSign = " "
    durHrs = int(durationSex / 60 / 60)
    durMin = int(durationSex / 60) % 60
    durSec = int(durationSex) % 60
    duration_format = "%s%01dh %02dm %02ds" % (durSign, durHrs, durMin, durSec)

    call = Call(number, date_millis, direction, date_format, duration_format)
    calls.append(call)
    if VERBOSE:
      print(str(call))
  return calls

def readMMSFromMsgDir(mmsMsgDir, mms_parts_dir):
  msgDirs = glob.glob(mmsMsgDir + "/*")

  mmsMessages = []
  keyValRegex = re.compile(r'^\s*(\w+)\s*=\s*"?(.*?)"?\s*$')
  for msgDir in sorted(msgDirs):
    msgInfo = msgDir + "/" + "info"
    if not os.path.isfile(msgInfo):
      print("missing \"info\" file for " + msgDir)
      quit(1)
    f = open(msgInfo)
    infoLines = f.read().splitlines()
    mms = MMS(mms_parts_dir)
    for infoLine in infoLines:
      m = keyValRegex.match(infoLine)
      if not m or len(m.groups()) != 2:
        print("malformed info line: " + infoLine)
        quit(1)
      key = m.group(1)
      val = m.group(2)
      if key == "from":
        mms.from_number = val
      elif key == "to":
        mms.to_numbers.append(val)
      elif key == "date":
        mms.date_millis = long(val)
        mms.date_format = time.strftime("%Y-%m-%d %H:%M:%S",
          time.localtime(mms.date_millis/1000))
      elif key == "date_sent":
        mms.date_sent_millis = long(val)
      elif key == "dir":
        if val not in MMS_DIR.__members__:
          print("invalid MMS direction: " + str(val))
          quit(1)
        mms.direction = MMS_DIR.__members__[val]
      elif key == "subject":
        mms.subject = unescapeStr(val).decode('utf-8')
      elif key == "body":
        mms.body = unescapeStr(val).decode('utf-8')
      elif key == "att":
        attName = val
        filepath = msgDir + "/" + val
        mms.attFiles[attName] = filepath
        mms.attFilesRemotePaths[attName] = REMOTE_MMS_PARTS_DIR + "/" + attName
      elif key == "checksum":
        mms.checksum = val
    mmsMessages.append(mms)
  return mmsMessages

def readMMSFromCommHistory(db_file, mms_parts_dir):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()
  i=0
  texts = []
  query = c.execute(
    'SELECT id, remoteUid, groupId, startTime, endTime, direction, subject, freeText \
     FROM Events \
     WHERE type = 6 \
     ORDER BY id ASC;')
  msgs = {}
  event_groups = {}
  for row in query:
    event_id = row[0]
    number = row[1]
    group_id = row[2]
    date_sent_millis = long(row[3]) * 1000
    date_millis = long(row[4]) * 1000
    dir_type_mms = row[5]
    subject = row[6]
    body = row[7]

    if subject == None:
      subject = ""
    if body == None:
      body = ""

    if dir_type_mms == 2:
      direction = MMS_DIR.OUT
    elif dir_type_mms == 1:
      direction = MMS_DIR.INC
    else:
      print("INVALID MMS DIRECTION TYPE: " + str(dir_type_mms) + "\n" + str(row))
      quit(1)

    date_format = time.strftime("%Y-%m-%d %H:%M:%S",
      time.localtime(date_millis/1000))

    msg = MMS(mms_parts_dir)
    msg.date_millis = date_millis
    msg.date_sent_millis = date_sent_millis
    msg.direction = direction
    msg.date_format = date_format
    msg.subject = subject
    msg.body = body

    msgs[event_id] = msg
    event_groups[event_id] = group_id

  query = c.execute(
    'SELECT eventId, contentType, path \
     FROM messageParts \
     ORDER BY id ASC;')

  for row in query:
    event_id = row[0]
    part_type = row[1]
    filepath = row[2]

    if event_id == None:
      print("WARNING: MMS part missing eventId (msg likely deleted): " + str(row))
      continue

    if event_id not in msgs:
      print("INVALID MESSAGE ID FOR MMS PART: " + str(row))
      quit(1)
    msg = msgs[event_id]

    part = MMSPart()
    part.part_type = part_type
    part.filepath = filepath
    msg.parts.append(part)

  for msg in msgs.values():
    msg.parseParts()

  query = c.execute(
    'SELECT id, remoteUids \
     FROM groups \
     ORDER BY id ASC;')

  group_numbers = {}
  for row in query:
    group_id = long(row[0])
    numbers = row[1]
    group_numbers[group_id] = numbers

  for event_id in msgs.keys():
    msg = msgs[event_id]
    group_id = event_groups[event_id]
    if group_id not in group_numbers:
      print("INVALID GROUP ID: " + str(group_id) + "\n" + str(msg))
      quit(1)
    groupNumber = group_numbers[group_id]
    if msg.direction == MMS_DIR.OUT:
      msg.from_number = cleanNumber(MY_NUMBER)
      msg.to_numbers.append(cleanNumber(groupNumber))
    elif msg.direction == MMS_DIR.INC:
      msg.from_number = cleanNumber(groupNumber)
      msg.to_numbers.append(cleanNumber(MY_NUMBER))

  return msgs.values()

def readCallsFromCSV(csvFile):
  try:
    csvFile = open(csvFile, 'r')
    csvContents = csvFile.read()
    csvFile.close()
  except IOError:
    print("could not read csv file: " + str(csvFile))
    quit(1)

  texts = []
  rowRegex = re.compile(''
    + r'([0-9+]+),'
    + r'(\d+),'
    + r'(' + '|'.join(sorted(CALL_DIR.__members__.keys())) + r'),'
    + r'([^,]*),'
    + r'(\s*-?\s*\d+h\s*\d+m\s*\d+s)'
    )
  for row in csvContents.splitlines():
    m = rowRegex.match(row)
    if not m or len(m.groups()) != 5:
      print("invalid CALL CSV line: " + row)
      quit(1)
    number           = m.group(1)
    date_millis      = int(m.group(2))
    directionStr     = m.group(3)
    date_format      = m.group(4)
    duration_format  = m.group(5)

    texts.append(Call( number
                     , date_millis
                     , CALL_DIR.__members__[directionStr]
                     , date_format
                     , duration_format
                     ))
  return texts

def getDbTableNames(db_file):
  cur = sqlite3.connect(db_file).cursor()
  names = cur.execute("SELECT name FROM sqlite_master WHERE type='table'; ")
  names = [name[0] for name in names]
  cur.close()
  return names

def insertRow(cursor, tableName, colVals):
  (colNames, values) = zip(*colVals.items())
  valuePlaceHolders = list(map(lambda val: "?", values))
  cursor.execute( " INSERT INTO " + tableName
                + " (" + ", ".join(colNames) + ")"
                + " VALUES (" + ", ".join(valuePlaceHolders) + ")"
                , values)

def ensureGroupNumbersInserted(cursor, numbers):
  groupIdByNumber = {}
  query = cursor.execute("SELECT id, remoteUids FROM groups;")
  maxGroupId = 0
  for row in query:
    groupId = long(row[0])
    remoteUids = row[1]

    if groupId > maxGroupId:
      maxGroupId = groupId

    if "|" not in remoteUids:
      number = remoteUids
      number = cleanNumber(number)
      groupIdByNumber[number] = groupId

  for number in numbers:
    #add new group if necessary
    if not number in groupIdByNumber:
      maxGroupId += 1
      insertRow(cursor, "groups", { "id": maxGroupId
                                  , "localUid": LOCAL_UID
                                  , "remoteUids": number
                                  , "type": 0
                                  , "chatName": ""
                                  , "lastModified": 0
                                  })
      groupIdByNumber[number] = maxGroupId

      if VERBOSE:
        print("added new group: " + str(number) + " => " + str(groupId))

  return groupIdByNumber

def importSMSToDb(texts, db_file):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()

  for txt in texts:
    txt.cleanNumber()

  allNumbers = set([txt.number for txt in texts])
  groupIdByNumber = ensureGroupNumbersInserted(c, allNumbers)

  startTime = time.time()
  count=0
  groupsSeen = set()
  elapsedS = 0
  smsPerSec = 0
  statusMsg = ""

  for txt in texts:
    groupId = groupIdByNumber[txt.number]

    if txt.isDirection(SMS_DIR.OUT):
      dir_type = 2
      status_type = 2
    elif txt.isDirection(SMS_DIR.INC):
      dir_type = 1
      status_type = 0

    messageToken = str(uuid.uuid4())

    #add message to events table
    insertRow(c, "events", { "type":                  2
                           , "startTime":             int(txt.date_sent_millis/1000)
                           , "endTime":               int(txt.date_millis/1000)
                           , "direction":             dir_type
                           , "isDraft":               0
                           , "isRead":                1
                           , "isMissedCall":          0
                           , "isEmergencyCall":       0
                           , "status":                status_type
                           , "bytesReceived":         0
                           , "localUid":              LOCAL_UID
                           , "remoteUid":             txt.number
                           , "parentId":              ""
                           , "subject":               ""
                           , "freeText":              txt.body
                           , "groupId":               int(groupId)
                           , "messageToken":          messageToken
                           , "lastModified":          0
                           , "vCardFileName":         ""
                           , "vCardLabel":            ""
                           , "isDeleted":             ""
                           , "reportDelivery":        0
                           , "validityPeriod":        0
                           , "contentLocation":       ""
                           , "messageParts":          ""
                           , "headers":               ""
                           , "readStatus":            0
                           , "reportRead":            0
                           , "reportedReadRequested": 0
                           , "mmsId":                 ""
                           , "isAction":              0
                           })

    count += 1
    groupsSeen.add(groupId)
    elapsedS = time.time() - startTime
    smsPerSec = int(count / elapsedS + 0.5)
    statusMsg = " {0:6d} SMS for {1:4d} contacts in {2:6.2f}s @ {3:5d} SMS/s".format(
                  count, len(groupsSeen), elapsedS, smsPerSec)

    if count % 100 == 0:
      sys.stdout.write("\r" + statusMsg)
      sys.stdout.flush()

  print("\n\nfinished:\n" + statusMsg)

  if not NO_COMMIT:
    conn.commit()
    print("changes saved to " + db_file)

  c.close()
  conn.close()

def importCallsToDb(calls, db_file):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()

  for call in calls:
    call.cleanNumber()

  startTime = time.time()
  count=0
  numbersSeen = set()
  elapsedS = 0
  callsPerSec = 0
  statusMsg = ""

  for call in calls:
    if call.isDirection(CALL_DIR.OUT):
      dir_type = 2
      isMissed = 0
      headersRejectedHack = ""
    elif call.isDirection(CALL_DIR.INC):
      dir_type = 1
      isMissed = 0
      headersRejectedHack = ""
    elif call.isDirection(CALL_DIR.MIS):
      dir_type = 1
      isMissed = 1
      headersRejectedHack = ""
    elif call.isDirection(CALL_DIR.REJ):
      dir_type = 1
      isMissed = 0
      headersRejectedHack = "rejected"

    startTime = int(call.date_millis/1000)
    endTime = startTime + call.getDurationSex()

    #add message to events table
    insertRow(c, "events", { "type":                  3
                           , "startTime":             startTime
                           , "endTime":               endTime
                           , "direction":             dir_type
                           , "isDraft":               0
                           , "isRead":                1
                           , "isMissedCall":          isMissed
                           , "isEmergencyCall":       0
                           , "status":                0
                           , "bytesReceived":         0
                           , "localUid":              LOCAL_UID
                           , "remoteUid":             call.number
                           , "parentId":              ""
                           , "subject":               ""
                           , "freeText":              ""
                           , "groupId":               ""
                           , "messageToken":          ""
                           , "lastModified":          startTime
                           , "vCardFileName":         ""
                           , "vCardLabel":            ""
                           , "isDeleted":             ""
                           , "reportDelivery":        0
                           , "validityPeriod":        0
                           , "contentLocation":       ""
                           , "messageParts":          ""
                           , "headers":               headersRejectedHack
                           , "readStatus":            0
                           , "reportRead":            0
                           , "reportedReadRequested": 0
                           , "mmsId":                 ""
                           , "isAction":              0
                           })

    count += 1
    numbersSeen.add(call.number)
    elapsedS = time.time() - startTime
    callsPerSec = int(count / elapsedS + 0.5)
    statusMsg = " {0:6d} calls for {1:4d} contacts in {2:6.2f}s @ {3:5d} calls/s".format(
                  count, len(numbersSeen), elapsedS, callsPerSec)

    if count % 100 == 0:
      sys.stdout.write("\r" + statusMsg)
      sys.stdout.flush()

  print("\n\nfinished:\n" + statusMsg)

  if not NO_COMMIT:
    conn.commit()
    print("changes saved to " + db_file)

  c.close()
  conn.close()

def importMMSToDb(mmsMessages, db_file):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()

  for mms in mmsMessages:
    mms.cleanNumbers()

  allNumbers = set([mms.from_number for mms in mmsMessages])
  allNumbers.update([to_number for mms in mmsMessages for to_number in mms.to_numbers])
  groupIdByNumber = ensureGroupNumbersInserted(c, allNumbers)

  startTime = time.time()
  count=0
  groupsSeen = set()
  elapsedS = 0
  mmsPerSec = 0
  statusMsg = ""

  for mms in mmsMessages:
    if len(mms.to_numbers) > 1:
      print("ERROR: group-MMS is not supported on sailfish\n" + str(mms))
      quit(1)
    if len(mms.to_numbers) < 1:
      print("ERROR: mms missing 'to' number\n" + str(mms))
      quit(1)

    to_number = mms.to_numbers[0]

    if mms.isDirection(MMS_DIR.OUT):
      dir_type = 2
      status_type = 2
      groupId = groupIdByNumber[to_number]
    elif mms.isDirection(MMS_DIR.INC):
      dir_type = 1
      status_type = -1
      groupId = groupIdByNumber[mms.from_number]
    else:
      print("ERROR: unsupported MMS dir type\n" + str(mms))
      quit(1)

    #add message to events table
    insertRow(c, "events", { "type":                  6
                           , "startTime":             int(mms.date_sent_millis/1000)
                           , "endTime":               int(mms.date_millis/1000)
                           , "direction":             dir_type
                           , "isDraft":               0
                           , "isRead":                1
                           , "isMissedCall":          0
                           , "isEmergencyCall":       0
                           , "status":                status_type
                           , "bytesReceived":         0
                           , "localUid":              LOCAL_UID
                           , "remoteUid":             mms.from_number
                           , "parentId":              ""
                           , "subject":               mms.subject
                           , "freeText":              mms.body
                           , "groupId":               int(groupId)
                           , "messageToken":          ""
                           , "lastModified":          int(mms.date_millis/1000)
                           , "vCardFileName":         ""
                           , "vCardLabel":            ""
                           , "isDeleted":             ""
                           , "reportDelivery":        0
                           , "validityPeriod":        0
                           , "contentLocation":       ""
                           , "messageParts":          ""
                           , "headers":               "x-mms-to" + to_number
                           , "readStatus":            0
                           , "reportRead":            0
                           , "reportedReadRequested": 0
                           , "mmsId":                 mms.checksum
                           , "isAction":              0
                           })
    eventId = c.lastrowid

    contentId = 1
    for attName in sorted(mms.attFiles.keys()):
      localFilepath = mms.attFiles[attName]
      remoteFilepath = mms.attFilesRemotePaths[attName]

      contentType = guessContentType(attName, localFilepath)

      insertRow(c, "messageParts", { "eventId":     eventId
                                   , "contentId":   contentId
                                   , "contentType": contentType
                                   , "path":        remoteFilepath
                                   })
      contentId += 1

    count += 1
    groupsSeen.add(groupId)
    elapsedS = time.time() - startTime
    mmsPerSec = int(count / elapsedS + 0.5)
    statusMsg = " {0:6d} MMS for {1:4d} contacts in {2:6.2f}s @ {3:5d} MMS/s".format(
                  count, len(groupsSeen), elapsedS, mmsPerSec)

    if count % 100 == 0:
      sys.stdout.write("\r" + statusMsg)
      sys.stdout.flush()

  print("\n\nfinished:\n" + statusMsg)

  if not NO_COMMIT:
    conn.commit()
    print("changes saved to " + db_file)

  c.close()
  conn.close()

def guessContentType(filename, filepath):
  if re.match(r'^.*\.(txt)$', filename, re.IGNORECASE):
    contentType = "text/plain;charset=utf-8"
  elif re.match(r'^.*\.(jpg|jpeg)$', filename, re.IGNORECASE):
    contentType = "image/jpeg"
  elif re.match(r'^.*\.(png)$', filename, re.IGNORECASE):
    contentType = "image/png"
  elif re.match(r'^.*\.(gif)$', filename, re.IGNORECASE):
    contentType = "image/gif"
  elif re.match(r'^.*\.(wav)$', filename, re.IGNORECASE):
    contentType = "audio/wav"
  elif re.match(r'^.*\.(flac)$', filename, re.IGNORECASE):
    contentType = "audio/flac"
  elif re.match(r'^.*\.(ogg)$', filename, re.IGNORECASE):
    contentType = "audio/ogg"
  elif re.match(r'^.*\.(mp3|mp2|m2a|mpga)$', filename, re.IGNORECASE):
    contentType = "audio/mpeg"
  elif re.match(r'^.*\.(mp4)$', filename, re.IGNORECASE):
    contentType = "video/mp4"
  elif re.match(r'^.*\.(mkv)$', filename, re.IGNORECASE):
    contentType = "video/x-matroska"
  elif re.match(r'^.*\.(webm)$', filename, re.IGNORECASE):
    contentType = "video/webm"
  elif re.match(r'^.*\.(mpg|mpeg|m1v|m2v)$', filename, re.IGNORECASE):
    contentType = "video/mpeg"
  elif re.match(r'^.*\.(avi)$', filename, re.IGNORECASE):
    contentType = "video/avi"
  elif re.match(r'^.*\.(3gp)$', filename, re.IGNORECASE):
    contentType = "video/3gpp"
  else:
    mimeType = result = subprocess.check_output([ "file"
                                                , "--mime"
                                                , "--brief"
                                                , filepath
                                                ])
    mimeType = re.sub(r';.*', '', mimeType)
    if re.match(r'^[a-z0-9]+/[a-z0-9\-.]+$', mimeType):
      return mimeType
    else:
      print("unknown file type: " + filepath)
      quit(1)

  return contentType

if __name__ == '__main__':
  main()
