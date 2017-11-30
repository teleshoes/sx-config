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

argHelp = { 'COMMAND':          ( 'import-to-db\n'
                                + '  extract SMS from <SMS_CSV_FILE>\n'
                                + '  and output to <DB_FILE>\n'
                                + '\n'
                                + 'export-from-db\n'
                                + '  extract SMS/MMS from <DB_FILE> and <MMS_PARTS_DIR>\n'
                                + '  and output to <SMS_CSV_FILE> and <MMS_MSG_DIR>\n'
                                )
          , '--sms-csv-file':   ( 'SMS CSV file to import-from/export-to')
          , '--call-csv-file':  ( 'calls CSV file to import-from/export-to')
          , '--db-file':        ( 'pre-existing commhistory.db file to import-to/export-from')
          , '--mms-parts-dir':  ( 'local copy of app_parts dir to import-to/expot-from\n'
                                + '  ' + REMOTE_MMS_PARTS_DIR + '\n'
                                )
          , '--mms-msg-dir':    ( 'directory of MMS messages to import-from/export-to')
          , '--from-number':    ( 'default phone number for "from" in outgoing MMS')
          , '--verbose':        ( 'verbose output, slower')
          , '--no-commit':      ( 'do not actually save changes, no SQL commit')
          , '--limit':          ( 'limit to the most recent <LIMIT> messages')
          }

SMS_DIR = Enum('SMS_DIR', ['OUT', 'INC'])
MMS_DIR = Enum('MMS_DIR', ['OUT', 'INC', 'NTF'])
CALL_DIR = Enum('CALL_DIR', ['OUT', 'INC', 'MIS', 'REJ'])

class UsageFormatter(argparse.HelpFormatter):
  def __init__(self, prog):
    argparse.HelpFormatter.__init__(self, prog)
    self._width = 100
    self._max_help_position = 40
  def _split_lines(self, text, width):
    return text.splitlines()

def main():
  parser = argparse.ArgumentParser(
    description='Import/export messages to/from android MMS/SMS database file.',
    formatter_class=UsageFormatter)
  parser.add_argument('COMMAND',           help=argHelp['COMMAND'])
  parser.add_argument('--db-file',         help=argHelp['--db-file'])
  parser.add_argument('--sms-csv-file',    help=argHelp['--sms-csv-file'])
  parser.add_argument('--call-csv-file',   help=argHelp['--call-csv-file'])
  parser.add_argument('--mms-parts-dir',   help=argHelp['--mms-parts-dir'], default="./app_parts")
  parser.add_argument('--mms-msg-dir',     help=argHelp['--mms-msg-dir'],   default="./mms_messages")
  parser.add_argument('--from-number',     help=argHelp['--from-number']),
  parser.add_argument('--verbose', '-v',   help=argHelp['--verbose'],       action='store_true')
  parser.add_argument('--no-commit', '-n', help=argHelp['--no-commit'],     action='store_true')
  parser.add_argument('--limit',           help=argHelp['--limit'],         type=int, default=0)
  args = parser.parse_args()

  global VERBOSE, NO_COMMIT, FROM_NUMBER
  VERBOSE = args.verbose
  NO_COMMIT = args.no_commit
  FROM_NUMBER = args.from_number

  if args.db_file == None:
    parser.print_help()
    print "\n--db-file is required"
    quit(1)

  if args.COMMAND == "export-from-db":
    if args.sms_csv_file == None:
      print "skipping SMS export, no <SMS_CSV_FILE> for writing to"
    else:
      texts = readTextsFromCommHistory(args.db_file)
      print "read " + str(len(texts)) + " SMS messages from " + args.db_file
      f = codecs.open(args.sms_csv_file, 'w', 'utf-8')
      for txt in texts:
        f.write(txt.toCsv() + "\n")
      f.close()

    if not os.path.isdir(args.mms_msg_dir):
      print "skipping MMS export, no <MMS_MSG_DIR> for writing to"
    elif not os.path.isdir(args.mms_parts_dir):
      print "skipping MMS export, no <MMS_PARTS_DIR> to read attachments from"
    else:
      mmsMessages = readMMSFromCommHistory(args.db_file, args.mms_parts_dir)
      print "read " + str(len(mmsMessages)) + " MMS messages from " + args.db_file
      attFileCount = 0
      for msg in mmsMessages:
        dirName = msg.getMsgDirName()
        msgDir = args.mms_msg_dir + "/" + dirName
        if not os.path.isdir(msgDir):
          os.mkdir(msgDir)
        infoFile = codecs.open(msgDir + "/" + "info", 'w', 'utf-8')
        infoFile.write(msg.getInfo())
        infoFile.close()
        for attName in sorted(msg.attFiles.keys()):
          srcFile = msg.attFiles[attName]
          destFile = msgDir + "/" + attName
          if 0 != os.system("cp -ar --reflink '" + srcFile + "' '" + destFile + "'"):
            print "failed to copy " + str(srcFile)
            quit(1)
          attFileCount += 1
      print "copied " + str(attFileCount) + " files from " + args.mms_parts_dir
  elif args.COMMAND == "import-to-db":
    texts = []
    if args.sms_csv_file == None or not os.path.isfile(args.sms_csv_file):
      print "skipping SMS import, no <SMS_CSV_FILE> for reading from"
    else:
      print "Reading texts from CSV file:"
      starttime = time.time()
      texts = readTextsFromCSV(args.sms_csv_file)
      print "finished in {0} seconds, {1} messages read".format( (time.time()-starttime), len(texts) )

      print "sorting all {0} texts by date".format(len(texts))
      texts = sorted(texts, key=lambda text: text.date_millis)

      if args.limit > 0:
        print "saving only the last {0} messages".format( args.limit )
        texts = texts[ (-args.limit) : ]

    calls = []
    if args.call_csv_file == None or not os.path.isfile(args.call_csv_file):
      print "skipping calls import, no <CALL_CSV_FILE> for reading from"
    else:
      print "Reading calls from CSV file:"
      starttime = time.time()
      calls = readCallsFromCSV(args.call_csv_file)
      print "finished in {0} seconds, {1} messages read".format( (time.time()-starttime), len(calls) )

      print "sorting all {0} calls by date".format(len(calls))
      calls = sorted(calls, key=lambda call: call.date_millis)

      if args.limit > 0:
        print "saving only the last {0} messages".format( args.limit )
        calls = calls[ (-args.limit) : ]

    mmsMessages = []
    if not os.path.isdir(args.mms_msg_dir):
      print "skipping MMS import, no <MMS_MSG_DIR> for reading from"
    elif not os.path.isdir(args.mms_parts_dir):
      print "skipping MMS import, no <MMS_PARTS_DIR> to write attachments to"
    else:
      print "reading mms from " + args.mms_msg_dir
      mmsMessages = readMMSFromMsgDir(args.mms_msg_dir, args.mms_parts_dir)
      attFileCount = 0
      for mms in mmsMessages:
        dirName = mms.getMsgDirName()
        msgDir = args.mms_msg_dir + "/" + dirName
        if not os.path.isdir(msgDir):
          print "error reading MMS(" + str(msgDir) + ":\n" + str(mms)
          quit(1)

        oldChecksum = mms.checksum
        mms.generateChecksum()
        newChecksum = mms.checksum

        if oldChecksum != newChecksum:
          print "mismatched checksum for MMS message"
          print mms
          quit(1)

        attFilePrefix = dirName
        for filename in sorted(list(mms.attFiles.keys())):
          srcFile = mms.attFiles[filename]
          # prefix any file that doesnt start with PART_<MILLIS>
          if re.match(r'^PART_\d{13}', filename):
            destFile = args.mms_parts_dir + "/" + filename
          else:
            destFile = args.mms_parts_dir + "/" + attFilePrefix + "_" + filename

          if os.path.isfile(destFile):
            if not filecmp.cmp(srcFile, destFile, shallow=False):
              print "ERROR: attFile exists in parts dir already and is different"
              quit(1)

          if 0 != os.system("cp -ar --reflink '" + srcFile + "' '" + destFile + "'"):
            print "failed to copy " + str(srcFile)
            quit(1)
          mms.attFiles[filename] = destFile
          attFileCount += 1

      print "read " + str(len(mmsMessages)) + " MMS messages"
      print "copied " + str(attFileCount) + " files to " + args.mms_parts_dir

    print "Saving changes into Android DB (commhistory.db), "+str(args.db_file)
    importMessagesToDb(texts, calls, mmsMessages, args.db_file)
  else:
    print "invalid <COMMAND>: " + args.COMMAND
    print "  (expected one of 'export-from-db' or 'import-to-db')"
    quit(1)

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
      print "invalid SMS direction: " + str(self.direction)
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
  def getDurationSex(self):
    durationRegex = re.compile(r'\s*(-?)\s*(\d+)h\s*(\d+)m\s*(\d+)s')
    m = durationRegex.match(self.duration_format)
    if not m or len(m.groups()) != 4:
      print "invalid duration format: " + self.duration_format
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
      print "invalid CALL direction: " + str(self.direction)
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
    self.checksum = None
  def parseParts(self):
    self.attFiles = {}
    self.checksum = None
    for p in self.parts:
      if 'smil' in p.part_type:
        pass
      elif p.filepath != None:
        relFilepath = p.filepath
        relFilepath = re.sub('^' + REMOTE_MMS_PARTS_DIR + '/', '', relFilepath)
        filename = relFilepath
        filename = re.sub('^\d+/', '', filename)
        if "/" in filename:
          print "filename contains path sep '/': " + filename
          quit(1)
        prefixRegex = re.compile(''
          + r'^\d+_'
          + r'([0-9+]+-)*[0-9+]+_'
          + r'(' + '|'.join(sorted(MMS_DIR.__members__.keys())) + r')_'
          + r'[0-9a-f]{32}_'
          )
        unprefixedFilename = prefixRegex.sub('', filename)
        attName = unprefixedFilename
        localFilepath = self.mms_parts_dir + "/" + relFilepath
        self.attFiles[attName] = localFilepath
      else:
        print "invalid MMS part: " + str(p)
        quit(1)
    self.checksum = self.generateChecksum()
  def generateChecksum(self):
    md5 = hashlib.md5()
    if self.subject != None:
      md5.update(escapeStr(self.subject.encode("utf-8")))
    if self.body != None:
      md5.update(escapeStr(self.body.encode("utf-8")))
    for attName in sorted(self.attFiles.keys()):
      md5.update("\n" + attName + "\n")
      filepath = self.attFiles[attName]
      if not os.path.isfile(filepath):
        print "missing att file: " + filepath
        quit(1)
      f = open(filepath, 'r')
      md5.update(f.read())
      f.close()
    return md5.hexdigest()
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
      print "invalid MMS direction: " + str(self.direction)
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
    print "could not read csv file: " + str(csvFile)
    quit(1)

  texts = []
  rowRegex = re.compile(''
    + r'([0-9+]+),'
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
      print "invalid SMS CSV line: " + row
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
      print "INVALID SMS DIRECTION TYPE: " + str(dir_type) + "\n" + str(row)
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
      print str(txt)
  return texts

def readMMSFromMsgDir(mmsMsgDir, mms_parts_dir):
  msgDirs = glob.glob(mmsMsgDir + "/*")

  mmsMessages = []
  keyValRegex = re.compile(r'^\s*(\w+)\s*=\s*"?(.*?)"?\s*$')
  for msgDir in sorted(msgDirs):
    msgInfo = msgDir + "/" + "info"
    if not os.path.isfile(msgInfo):
      print "missing \"info\" file for " + msgDir
      quit(1)
    f = open(msgInfo)
    infoLines = f.read().splitlines()
    mms = MMS(mms_parts_dir)
    for infoLine in infoLines:
      m = keyValRegex.match(infoLine)
      if not m or len(m.groups()) != 2:
        print "malformed info line: " + infoLine
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
          print "invalid MMS direction: " + str(val)
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
      print "INVALID MMS DIRECTION TYPE: " + str(dir_type_mms) + "\n" + str(row)
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
    if direction == MMS_DIR.OUT:
      msg.from_number = cleanNumber(FROM_NUMBER)
    else:
      msg.from_number = cleanNumber(number)


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

    if event_id not in msgs:
      print "INVALID MESSAGE ID FOR MMS PART: " + str(row)
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
      print "INVALID GROUP ID: " + str(group_id) + "\n" + str(msg)
      quit(1)
    numbers = group_numbers[group_id]
    for number in numbers.split("|"):
      msg.to_numbers.append(cleanNumber(number))

  return msgs.values()

def readCallsFromCSV(csvFile):
  try:
    csvFile = open(csvFile, 'r')
    csvContents = csvFile.read()
    csvFile.close()
  except IOError:
    print "could not read csv file: " + str(csvFile)
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
      print "invalid CALL CSV line: " + row
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

def importMessagesToDb(texts, calls, mmsMessages, db_file):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()

  for txt in texts:
    txt.number = cleanNumber(txt.number)
  for call in calls:
    call.number = cleanNumber(call.number)
  for mms in mmsMessages:
    mms.from_number = cleanNumber(mms.from_number)
    toNumbers = []
    for toNumber in mms.to_numbers:
      toNumbers.append(cleanNumber(toNumber))
    mms.to_numbers = toNumbers

  allNumbers = set()
  for txt in texts:
    allNumbers.add(txt.number)
  for call in calls:
    allNumbers.add(call.number)
  for mms in mmsMessages:
    allNumbers.add(mms.from_number)
    for toNumber in mms.to_numbers:
      allNumbers.add(toNumber)

  maxGroupId = 0
  groupIdByNumber = {}
  query = c.execute("SELECT id, remoteUids FROM groups;")
  for row in query:
    groupId = long(row[0])
    numbers = row[1]

    if groupId > maxGroupId:
      maxGroupId = groupId

    if "|" not in numbers:
      number = numbers
      number = cleanNumber(number)
      groupIdByNumber[number] = groupId

  for number in allNumbers:
    #add new group if necessary
    if not number in groupIdByNumber:
      maxGroupId += 1
      insertRow(c, "groups", { "id": maxGroupId
                             , "localUid": LOCAL_UID
                             , "remoteUids": number
                             , "type": 0
                             , "chatName": ""
                             , "lastModified": 0
                             })
      groupIdByNumber[number] = maxGroupId

      if VERBOSE:
        print "added new group: " + str(number) + " => " + str(groupId)

  for mms in mmsMessages:
    numbers = []
    if mms.isOutgoing():
      for toNumber in mms.to_numbers:
        numbers.append(toNumber)
    elif mms.isIncoming():
      numbers.append(mms.from_number)

    for number in numbers:
      contactId = contactIdByNumber[number]

      #insertRow(c, "pdu", { "thread_id":   threadId
      #                    , "date":        int(mms.date_millis / 1000)
      #                    , "date_sent":   int(mms.date_sent_millis / 1000)
      #                    , "sub":         mms.subject
      #                    })
      #msgId = c.lastrowid

      for attName in sorted(mms.attFiles.keys()):
        localFilepath = mms.attFiles[attName]
        filename = re.sub(r'^.*/', '', localFilepath)
        remoteFilepath = REMOTE_MMS_PARTS_DIR + "/" + filename

        contentType = guessContentType(attName, localFilepath)

        #insertRow(c, "part", { "mid":   msgId
        #                     , "ct":    contentType
        #                     , "name":  filename
        #                     , "text":  None
        #                     })

  startTime = time.time()
  count=0
  numbersSeen = set()
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
                           , "hasExtraProperties":    0
                           , "hasMessageParts":       0
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

  startTime = time.time()
  count=0
  groupsSeen = set()
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
                           , "hasExtraProperties":    0
                           , "hasMessageParts":       0
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

  print "\n\nfinished:\n" + statusMsg

  if not NO_COMMIT:
    conn.commit()
    print "changes saved to " + db_file

  c.close()
  conn.close()

def guessContentType(filename, filepath):
  if re.match(r'^.*\.(jpg|jpeg)$', filename, re.IGNORECASE):
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
      print "unknown file type: " + filepath
      quit(1)

  return contentType

if __name__ == '__main__':
  main()
