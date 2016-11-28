#!/usr/bin/python
import argparse, codecs, re, sys, time, sqlite3, os.path, hashlib, glob, filecmp

VERBOSE = False
NO_COMMIT = False
REMOTE_MMS_PARTS_DIR = "/data/user/0/com.android.providers.telephony/app_parts"

argHelp = { 'COMMAND':          ( 'import-to-db\n'
                                + '  extract SMS from <CSV_FILE>\n'
                                + '  and output to <DB_FILE>\n'
                                + '\n'
                                + 'export-from-db\n'
                                + '  extract SMS/MMS from <DB_FILE> and <MMS_PARTS_DIR>\n'
                                + '  and output to <CSV_FILE> and <MMS_MSG_DIR>\n'
                                )
          , '--csv-file':       ( 'CSV file to import-from/export-to')
          , '--db-file':        ( 'pre-existing mmssms.db file to import-to/export-from')
          , '--mms-parts-dir':  ( 'local copy of app_parts dir to import-to/expot-from\n'
                                + '  ' + REMOTE_MMS_PARTS_DIR + '\n'
                                )
          , '--mms-msg-dir':    ( 'directory of MMS messages to import-from/export-to')
          , '--verbose':        ( 'verbose output, slower')
          , '--no-commit':      ( 'do not actually save changes, no SQL commit')
          , '--limit':          ( 'limit to the most recent <LIMIT> messages')
          }

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
  parser.add_argument('--csv-file',        help=argHelp['--csv-file'])
  parser.add_argument('--db-file',         help=argHelp['--db-file'])
  parser.add_argument('--mms-parts-dir',   help=argHelp['--mms-parts-dir'], default="./app_parts")
  parser.add_argument('--mms-msg-dir',     help=argHelp['--mms-msg-dir'],   default="./mms_messages")
  parser.add_argument('--verbose', '-v',   help=argHelp['--verbose'],       action='store_true')
  parser.add_argument('--no-commit', '-n', help=argHelp['--no-commit'],     action='store_true')
  parser.add_argument('--limit',           help=argHelp['--limit'],         type=int, default=0)
  args = parser.parse_args()

  global VERBOSE, NO_COMMIT
  VERBOSE = args.verbose
  NO_COMMIT = args.no_commit

  if args.csv_file == None:
    parser.print_help()
    print "\n--csv-file is required"
    quit(1)
  if args.db_file == None:
    parser.print_help()
    print "\n--db-file is required"
    quit(1)

  if args.COMMAND == "export-from-db":
    texts = readTextsFromAndroid(args.db_file)
    print "read " + str(len(texts)) + " SMS messages from " + args.db_file
    f = codecs.open(args.csv_file, 'w', 'utf-8')
    for txt in texts:
      f.write(txt.toCsv() + "\n")
    f.close()

    if not os.path.isdir(args.mms_msg_dir):
      print "skipping MMS export, no <MMS_MSG_DIR> for writing to"
    elif not os.path.isdir(args.mms_parts_dir):
      print "skipping MMS export, no <MMS_PARTS_DIR> to read attachments from"
    else:
      mmsMessages = readMMSFromAndroid(args.db_file, args.mms_parts_dir)
      print "read " + str(len(mmsMessages)) + " MMS messages from " + args.db_file
      attFileCount = 0
      for msg in mmsMessages:
        dirName = msg.getMsgDirName()
        msgDir = args.mms_msg_dir + "/" + dirName
        if not os.path.isdir(msgDir):
          os.mkdir(msgDir)
        infoFile = open(msgDir + "/" + "info", 'w')
        infoFile.write(msg.getInfo())
        infoFile.close()
        for attFile in msg.attFiles:
          srcFile = args.mms_parts_dir + "/" + attFile
          destFile = msgDir + "/" + attFile
          if 0 != os.system("cp -ar --reflink '" + srcFile + "' '" + destFile + "'"):
            print "failed to copy " + str(srcFile)
            quit(1)
          attFileCount += 1
      print "copied " + str(attFileCount) + " files from " + args.mms_parts_dir
  elif args.COMMAND == "import-to-db":
    print "Reading texts from CSV file:"
    starttime = time.time()
    texts = readTextsFromCSV(args.csv_file)
    print "finished in {0} seconds, {1} messages read".format( (time.time()-starttime), len(texts) )

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
          print "error reading MMS:\n" + mms
          quit(1)

        oldChecksum = mms.checksum
        mms.generateChecksum()
        newChecksum = mms.checksum

        if oldChecksum != newChecksum:
          print "mismatched checksum for MMS message"
          print mms
          quit(1)

        attFilePrefix = dirName
        for filename in list(mms.attFiles.keys()):
          srcFile = mms.attFiles[filename]
          # prefix any file that doesnt start with PART_<MILLIS>
          if re.match(r'^PART_\d{13}_', filename):
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

    print "sorting all {0} texts by date".format( len(texts) )
    texts = sorted(texts, key=lambda text: text.date_millis)

    if args.limit > 0:
      print "saving only the last {0} messages".format( args.limit )
      texts = texts[ (-args.limit) : ]

    print "Saving changes into Android DB (mmssms.db), "+str(args.db_file)
    importMessagesToDb(texts, mmsMessages, args.db_file)
  else:
    print "invalid <COMMAND>: " + args.COMMAND
    print "  (expected one of 'export-from-db' or 'import-to-db')"
    quit(1)

class Text:
  def __init__( self, number, date_millis, date_sent_millis,
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
      + "," + self.direction
      + "," + self.date_format
      + "," + "\"" + escapeStr(self.body) + "\""
    )
  def isDirOut(self):
    if self.direction == "OUT":
      return True
    elif self.direction == "INC":
      return False
    else:
      print "invalid SMS direction: " + str(self.direction)
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
    self.isNotificationInd = False

    self.parts = []
    self.body = None
    self.attFiles = {}
    self.checksum = None
  def parseParts(self):
    self.body = None
    self.attFiles = {}
    self.checksum = None
    for p in self.parts:
      if 'smil' in p.part_type:
        pass
      elif p.body != None:
        if self.body != None:
          print "multiple text parts found for mms: " + str(self)
          quit(1)
        self.body = p.body
      elif p.filepath != None:
        filename = p.filepath
        filename = re.sub('^' + REMOTE_MMS_PARTS_DIR + '/', '', filename)
        if "/" in filename:
          print "filename contains path sep '/': " + filename
          quit(1)
        unprefixedFilename = re.sub(r'^\d+_([0-9+]+-)*[0-9+]+_(INC|OUT)_[0-9a-f]{32}_', '', filename)
        attName = unprefixedFilename
        localFilepath = self.mms_parts_dir + "/" + filename
        self.attFiles[attName] = localFilepath
      else:
        print "invalid MMS part: " + str(p)
        quit(1)
    if self.body == None:
      self.body = ""
    self.checksum = self.generateChecksum()
  def generateChecksum(self):
    md5 = hashlib.md5()
    if self.subject != None:
      md5.update(self.subject.encode("utf-8"))
    if self.body != None:
      md5.update(self.body.encode("utf-8"))
    for attName in self.attFiles.keys():
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
    if self.isDirOut():
      dirName += "-".join(self.to_numbers)
    else:
      dirName += str(self.from_number)
    dirName += "_"
    dirName += str(self.direction)
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
    info += "dir=" + str(self.direction) + "\n"
    info += "date=" + str(self.date_millis) + "\n"
    info += "date_sent=" + str(date_sent_millis) + "\n"
    info += "subject=\"" + escapeStr(str(self.subject)) + "\"\n"
    info += "body=\"" + escapeStr(str(self.body)) + "\"\n"
    for attName in self.attFiles.keys():
      info += "att=" + str(attName) + "\n"
    info += "checksum=" + str(self.checksum) + "\n"
    return info
  def isDirOut(self):
    if self.direction == "OUT":
      return True
    elif self.direction == "INC":
      return False
    else:
      print "invalid MMS direction: " + str(self.direction)
  def __unicode__(self):
    return self.getInfo()
  def __str__(self):
    return unicode(self).encode('utf-8')

class MMSPart:
  def __init__(self):
    self.part_type = None
    self.filename = None
    self.filepath = None
    self.body = None

def cleanNumber(number):
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
  rowRegex = re.compile(r'([0-9+]+),(\d+),(\d+),(S|M),(INC|OUT),([^,]*),\"(.*)\"')
  for row in csvContents.splitlines():
    m = rowRegex.match(row)
    if not m or len(m.groups()) != 7:
      print "invalid SMS CSV line: " + row
      quit(1)
    number           = m.group(1)
    date_millis      = m.group(2)
    date_sent_millis = m.group(3)
    sms_mms_type     = m.group(4)
    direction        = m.group(5)
    date_format      = m.group(6)
    body             = unescapeStr(m.group(7)).decode('utf-8')

    texts.append(Text( number
                     , date_millis
                     , date_sent_millis
                     , sms_mms_type
                     , direction
                     , date_format
                     , body
                     ))
  return texts

def readTextsFromAndroid(db_file):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()
  i=0
  texts = []
  query = c.execute(
    'SELECT address, date, date_sent, type, body \
     FROM sms \
     ORDER BY _id ASC;')
  for row in query:
    number = row[0]
    date_millis = long(row[1])
    date_sent_millis = long(row[2])
    sms_mms_type = "S"
    dir_type = row[3]
    if dir_type == 2:
      direction = "OUT"
    elif dir_type == 1:
      direction = "INC"
    else:
      print "INVALID SMS DIRECTION TYPE: " + str(dir_type)
      quit(1)
    body = row[4]
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
        mms.direction = val
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

def readMMSFromAndroid(db_file, mms_parts_dir):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()
  i=0
  texts = []
  query = c.execute(
    'SELECT _id, date, date_sent, m_type, sub \
     FROM pdu \
     ORDER BY _id ASC;')
  msgs = {}
  for row in query:
    msg_id = row[0]
    date_millis = long(row[1]) * 1000
    date_sent_millis = long(row[2]) * 1000
    dir_type_mms = row[3]
    subject = row[4]

    if subject == None:
      subject = ""

    isNotificationInd = False

    if dir_type_mms == 128:
      direction = "OUT"
    elif dir_type_mms == 130:
      direction = "INC"
      isNotificationInd = True
    elif dir_type_mms == 132:
      direction = "INC"
    else:
      print "INVALID MMS DIRECTION TYPE: " + str(dir_type_mms)
      quit(1)

    date_format = time.strftime("%Y-%m-%d %H:%M:%S",
      time.localtime(date_millis/1000))

    msg = MMS(mms_parts_dir)
    msg.date_millis = date_millis
    msg.date_sent_millis = date_sent_millis
    msg.direction = direction
    msg.date_format = date_format
    msg.subject = subject
    msg.isNotificationInd = isNotificationInd

    msgs[msg_id] = msg

  query = c.execute(
    'SELECT mid, ct, name, _data, text \
     FROM part \
     ORDER BY _id ASC;')

  for row in query:
    msg_id = row[0]
    part_type = row[1]
    filename = row[2]
    filepath = row[3]
    body = row[4]

    if msg_id not in msgs:
      print "INVALID MESSAGE ID FOR ADDRESS: " + str(row)
      quit(1)
    msg = msgs[msg_id]

    part = MMSPart()
    part.part_type = part_type
    part.filename = filename
    part.filepath = filepath
    part.body = body
    msg.parts.append(part)

  for msg in msgs.values():
    msg.parseParts()

  query = c.execute(
    'SELECT msg_id, address, type \
     FROM addr \
     ORDER BY msg_id ASC;')

  for row in query:
    msg_id = row[0]
    number = row[1]
    dir_type_addr = row[2]

    is_sender_addr = False
    is_recipient_addr = False
    if dir_type_addr == 137:
      is_sender_addr = True
    elif dir_type_addr == 151:
      is_recipient_addr = True
    else:
      print "INVALID MMS ADDRESS DIRECTION: " + str(dir_type_addr)
      quit(1)

    if msg_id not in msgs:
      print "INVALID MESSAGE ID FOR ADDRESS: " + str(row)
      quit(1)
    msg = msgs[msg_id]

    if is_sender_addr:
      if msg.from_number != None:
        print "too many sender addresses" + str(row)
        quit(1)
      msg.from_number = cleanNumber(number)
    elif is_recipient_addr:
      msg.to_numbers.append(cleanNumber(number))

  mmsMessages = []
  for msg in msgs.values():
    if msg.isNotificationInd:
      print "IGNORING NOTIFICATION_IND: " + str(msg)
    else:
      mmsMessages.append(msg)

  return mmsMessages

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

def importMessagesToDb(texts, mmsMessages, db_file):
  conn = sqlite3.connect(db_file)
  c = conn.cursor()

  for txt in texts:
    txt.number = cleanNumber(txt.number)
  for mms in mmsMessages:
    mms.from_number = cleanNumber(mms.from_number)
    toNumbers = []
    for toNumber in mms.to_numbers:
      toNumbers.append(cleanNumber(toNumber))
    mms.to_numbers = toNumbers

  allNumbers = set()
  for txt in texts:
    allNumbers.add(txt.number)
  for mms in mmsMessages:
    allNumbers.add(mms.from_number)
    for toNumber in mms.to_numbers:
      allNumbers.add(toNumber)

  contactIdByNumber = {}
  canonicalAddressByNumber = {}
  query = c.execute("SELECT _id, address FROM canonical_addresses;")
  for row in query:
    contactId = row[0]
    addr = row[1]
    number = cleanNumber(addr)
    contactIdByNumber[number] = contactId
    canonicalAddressByNumber[number] = addr

  for number in allNumbers:
    #add canonical addr and thread
    if not number in contactIdByNumber:
      insertRow(c, "canonical_addresses", {"address": number})
      contactId = c.lastrowid
      insertRow(c, "threads", {"recipient_ids": contactId})
      contactIdByNumber[number] = contactId
      canonicalAddressByNumber[number] = number

      if VERBOSE:
        print "added new contact addr: " + str(number) + " => " + str(contactId)

  for mms in mmsMessages:
    numbers = []
    if mms.isDirOut():
      for toNumber in mms.to_numbers:
        numbers.append(toNumber)
    else:
      numbers.append(mms.from_number)

    for number in numbers:
      contactId = contactIdByNumber[number]

      c.execute(""
        + " UPDATE threads SET"
        + "   message_count = message_count + 1,"
        + "   snippet=?,"
        + "   'date'=?"
        + " WHERE recipient_ids=?"
        , [ mms.body
          , mms.date_millis
          , contactId])
      c.execute(""
        + " SELECT _id"
        + " FROM threads"
        + " WHERE recipient_ids=?"
        , [contactId])
      threadId = c.fetchone()[0]

      insertRow(c, "pdu", { "thread_id":   threadId
                          , "date":        int(mms.date_millis / 1000)
                          , "date_sent":   int(mms.date_sent_millis / 1000)
                          , "msg_box":     1
                          , "read":        1
                          , "m_id":        None
                          , "sub":         mms.subject
                          , "sub_cs":      None
                          , "ct_t":        "application/vnd.wap.multipart.related"
                          , "ct_l":        None
                          , "exp":         None
                          , "m_cls":       None
                          , "m_type":      128 if mms.isDirOut() else 132
                          , "v":           18
                          , "m_size":      None
                          , "pri":         None
                          , "rr":          None
                          , "rpt_a":       None
                          , "resp_st":     None
                          , "st":          None
                          , "tr_id":       None
                          , "retr_st":     None if mms.isDirOut() else 128
                          , "retr_txt":    None
                          , "retr_txt_cs": None
                          , "read_status": None
                          , "ct_cls":      None
                          , "resp_txt":    None
                          , "d_tm":        None
                          , "d_rpt":       None
                          , "locked":      0
                          , "sub_id":      1
                          , "phone_id":    -1
                          , "seen":        1
                          , "creator":     None
                          , "text_only":   1 if len(mms.attFiles) == 0 else 0
                          })
      msgId = c.lastrowid

      insertRow(c, "addr", { "msg_id":     msgId
                           , "contact_id": None  #always null
                           , "address":    canonicalAddressByNumber[mms.from_number]
                           , "type":       137   #sender address
                           , "charset":    3     #? - sometimes the character set is 106
                           })
      for toNumber in mms.to_numbers:
        insertRow(c, "addr", { "msg_id":     msgId
                             , "contact_id": None  #always null
                             , "address":    canonicalAddressByNumber[toNumber]
                             , "type":       151   #recipient address
                             , "charset":    3     #? - sometimes the character set is 106
                             })

      nextContentId = 0
      for attName in mms.attFiles.keys():
        localFilepath = mms.attFiles[attName]
        filename = re.sub(r'^.*/', '', localFilepath)
        remoteFilepath = REMOTE_MMS_PARTS_DIR + "/" + filename

        if re.match(r'^.*\.(jpg|jpeg)$', attName, re.IGNORECASE):
          contentType = "image/jpeg"
        elif re.match(r'^.*\.(png)$', attName, re.IGNORECASE):
          contentType = "image/png"
        elif re.match(r'^.*\.(gif)$', attName, re.IGNORECASE):
          contentType = "image/gif"
        elif re.match(r'^.*\.(wav)$', attName, re.IGNORECASE):
          contentType = "audio/wav"
        elif re.match(r'^.*\.(flac)$', attName, re.IGNORECASE):
          contentType = "audio/flac"
        elif re.match(r'^.*\.(ogg)$', attName, re.IGNORECASE):
          contentType = "audio/ogg"
        elif re.match(r'^.*\.(mp3|mp2|m2a|mpga)$', attName, re.IGNORECASE):
          contentType = "audio/mpeg"
        elif re.match(r'^.*\.(mp4)$', attName, re.IGNORECASE):
          contentType = "video/mp4"
        elif re.match(r'^.*\.(mkv)$', attName, re.IGNORECASE):
          contentType = "video/x-matroska"
        elif re.match(r'^.*\.(webm)$', attName, re.IGNORECASE):
          contentType = "video/webm"
        elif re.match(r'^.*\.(mpg|mpeg|m1v|m2v)$', attName, re.IGNORECASE):
          contentType = "video/mpeg"
        elif re.match(r'^.*\.(avi)$', attName, re.IGNORECASE):
          contentType = "video/avi"
        elif re.match(r'^.*\.(3gp)$', attName, re.IGNORECASE):
          contentType = "video/3gpp"
        else:
          print "unknown file type: " + attName
          quit(1)

        insertRow(c, "part", { "mid":   msgId
                             , "seq":   0
                             , "ct":    contentType
                             , "name":  filename
                             , "chset": None
                             , "cd":    None
                             , "fn":    None
                             , "cid":   "<" + str(nextContentId) + ">"
                             , "cl":    filename
                             , "ctt_s": None
                             , "ctt_t": None
                             , "_data": remoteFilepath
                             , "text":  None
                             })
        nextContentId += 1

      insertRow(c, "part", { "mid":   msgId
                           , "seq":   0
                           , "ct":    "text/plain"
                           , "name":  "body.txt"
                           , "chset": 3     #? - sometimes the character set is 106
                           , "cd":    None
                           , "fn":    None
                           , "cid":   "<" + str(nextContentId) + ">"
                           , "cl":    filename
                           , "ctt_s": None
                           , "ctt_t": None
                           , "_data": None
                           , "text":  mms.body
                           })
      nextContentId += 1

  startTime = time.time()
  count=0
  contactsSeen = set()
  elapsedS = 0
  smsPerSec = 0
  statusMsg = ""

  for txt in texts:
    contactId = contactIdByNumber[txt.number]

    c.execute(""
      + " UPDATE threads SET"
      + "   message_count = message_count + 1,"
      + "   snippet=?,"
      + "   'date'=?"
      + " WHERE recipient_ids=?"
      , [ txt.body
        , txt.date_millis
        , contactId])
    c.execute(""
      + " SELECT _id"
      + " FROM threads"
      + " WHERE recipient_ids=?"
      , [contactId])
    threadId = c.fetchone()[0]

    if VERBOSE:
      print "thread_id = "+ str(threadId)
      c.execute(""
        + " SELECT *"
        + " FROM threads"
        + " WHERE _id=?"
        , [contactId])
      print "updated thread: " + str(c.fetchone())
      print "adding entry to message db: " + str(txt)

    if txt.isDirOut():
      dir_type = 2
    else:
      dir_type = 1

    #add message to sms table
    insertRow(c, "sms", { "address":     canonicalAddressByNumber[txt.number]
                        , "date":        txt.date_millis
                        , "date_sent":   txt.date_sent_millis
                        , "body":        txt.body
                        , "thread_id":   threadId
                        , "type":        dir_type
                        , "read":        1
                        , "seen":        1
                        })

    count += 1
    contactsSeen.add(contactId)
    elapsedS = time.time() - startTime
    smsPerSec = int(count / elapsedS + 0.5)
    statusMsg = " {0:6d} SMS for {1:4d} contacts in {2:6.2f}s @ {3:5d} SMS/s".format(
                  count, len(contactsSeen), elapsedS, smsPerSec)

    if count % 100 == 0:
      sys.stdout.write("\r" + statusMsg)
      sys.stdout.flush()

  print "\n\nfinished:\n" + statusMsg

  if VERBOSE:
    print "\n\nthreads: "
    for row in c.execute('SELECT * FROM threads'):
      print row

  if not NO_COMMIT:
    conn.commit()
    print "changes saved to " + db_file

  c.close()
  conn.close()

if __name__ == '__main__':
  main()
