#!/usr/bin/python
import argparse, codecs, re, sys, time, sqlite3, os.path, hashlib

VERBOSE = False
NO_COMMIT = False

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
                                + '  /data/**/com.android.providers.telephony/app_parts/\n'
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

def sms_main():
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
    quit()
  if args.db_file == None:
    parser.print_help()
    print "\n--db-file is required"
    quit()

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
      msgs = readMMSFromAndroid(args.db_file, args.mms_parts_dir)
      print "read " + str(len(msgs)) + " MMS messages from " + args.db_file
      attFileCount = 0
      for msg in msgs.values():
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
            quit()
          attFileCount += 1
      print "copied " + str(attFileCount) + " files from " + args.mms_parts_dir
  elif args.COMMAND == "import-to-db":
    print "Reading texts from CSV file:"
    starttime = time.time()
    texts = readTextsFromCSV(args.csv_file)
    print "finished in {0} seconds, {1} messages read".format( (time.time()-starttime), len(texts) )

    print "sorting all {0} texts by date".format( len(texts) )
    texts = sorted(texts, key=lambda text: text.date_millis)

    if args.limit > 0:
      print "saving only the last {0} messages".format( args.limit )
      texts = texts[ (-args.limit) : ]

    print "Saving changes into Android DB (mmssms.db), "+str(args.db_file)
    importMessagesToDb(texts, args.db_file)
  else:
    print "invalid <COMMAND>: " + args.COMMAND
    print "  (expected one of 'export-from-db' or 'import-to-db')"
    quit()

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
  def __str__(self):
    return self.toCsv()

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

class MMS:
  def __init__(self, mms_parts_dir):
    self.mms_parts_dir = mms_parts_dir
    self.msg_id = None
    self.from_number = None
    self.to_numbers = []
    self.date_millis = None
    self.date_sent_millis = None
    self.direction = None
    self.date_format = None
    self.subject = None

    self.parts = []
    self.body = None
    self.attFiles = []
    self.checksum = None
  def parseParts(self):
    self.body = None
    self.attFiles = []
    self.checksum = None
    for p in self.parts:
      if 'smil' in p.part_type:
        pass
      elif p.body != None:
        if self.body != None:
          print "multiple text parts found for mms: " + str(self)
          quit()
        self.body = p.body
      elif p.filepath != None:
        filename = p.filepath
        filename = re.sub(r'/data/user/.*/com.android.providers.telephony/app_parts/', '', filename)
        if "/" in filename:
          print "filename contains path sep '/': " + filename
          quit()
        self.attFiles.append(filename)
      else:
        print "invalid MMS part: " + str(p)
        quit()
    if self.body == None:
      self.body = ""
    self.checksum = self.generateChecksum()
  def generateChecksum(self):
    md5 = hashlib.md5()
    if self.subject != None:
      md5.update(self.subject)
    if self.body != None:
      md5.update(self.body)
    for attFile in self.attFiles:
      md5.update("\n" + attFile + "\n")
      filepath = self.mms_parts_dir + "/" + attFile
      if not os.path.isfile(filepath):
        print "missing att file: " + filepath
        quit()
      f = open(filepath, 'r')
      md5.update(f.read())
      f.close()
    return md5.hexdigest()
  def getMsgDirName(self):
    dirName = ""
    dirName += str(self.date_millis)
    dirName += "_"
    if self.direction == "INC":
      dirName += str(self.from_number)
    elif self.direction == "OUT":
      dirName += "-".join(self.to_numbers)
    else:
      print "invalid direction: " + str(self.direction)
      quit()
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
    for attFile in self.attFiles:
      info += "att=" + str(attFile) + "\n"
    info += "checksum=" + str(self.checksum) + "\n"
    return info
  def __str__(self):
    return self.getInfo()

class MMSPart:
  def __init__(self):
    self.msg_id = None
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
    quit()

  texts = []
  rowRegex = re.compile(r'([0-9+]+),(\d+),(\d+),(S|M),(INC|OUT),([^,]*),\"(.*)\"')
  for row in csvContents.splitlines():
    m = rowRegex.match(row)
    if not m or len(m.groups()) != 7:
      print "invalid SMS CSV line: " + row
      quit()
    number           = m.group(1)
    date_millis      = m.group(2)
    date_sent_millis = m.group(3)
    sms_mms_type     = m.group(4)
    direction        = m.group(5)
    date_format      = m.group(6)
    body             = (m.group(7)
      .replace('&', '&amp;')
      .replace('\\\\', '&backslash;')
      .replace('\\n', '\n')
      .replace('\\r', '\r')
      .replace('\\"', '"')
      .replace('&backslash;', '\\')
      .replace('&amp;', '&')
      .decode('utf-8')
    )

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
    body = row[4]
    date_format = time.strftime("%Y-%m-%d %H:%M:%S",
      time.localtime(date_millis/1000))

    txt = Text(number, date_millis, date_sent_millis,
      sms_mms_type, direction, date_format, body)
    texts.append(txt)
    if VERBOSE:
      print txt.toCsv()
  return texts

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

    if dir_type_mms == 128:
      direction = "OUT"
    elif dir_type_mms == 132:
      direction = "INC"
    else:
      print "INVALID MMS DIRECTION TYPE: " + str(dir_type_mms)
      quit()

    date_format = time.strftime("%Y-%m-%d %H:%M:%S",
      time.localtime(date_millis/1000))

    msg = MMS(mms_parts_dir)
    msg.msg_id = msg_id
    msg.date_millis = date_millis
    msg.date_sent_millis = date_sent_millis
    msg.direction = direction
    msg.date_format = date_format
    msg.subject = subject

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

    msg = msgs[msg_id]
    if msg == None:
      print "INVALID MESSAGE ID FOR PART: " + str(row)
      quit()

    part = MMSPart()
    part.msg_id = msg_id
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
      print "INVALID ADDRESS DIRECTION: " + str(dir_type_addr)
      quit()

    msg = msgs[msg_id]
    if msg == None:
      print "INVALID MESSAGE ID FOR ADDRESS: " + str(row)
      quit()

    if is_sender_addr:
      if msg.from_number != None:
        print "too many sender addresses" + str(row)
        quit()
      msg.from_number = cleanNumber(number)
    elif is_recipient_addr:
      msg.to_numbers.append(cleanNumber(number))

  return msgs

def getDbTableNames(db_file):
  cur = sqlite3.connect(db_file).cursor()
  names = cur.execute("SELECT name FROM sqlite_master WHERE type='table'; ")
  names = [name[0] for name in names]
  cur.close()
  return names

def importMessagesToDb(texts, db_file):
  #open resources
  conn = sqlite3.connect(db_file)
  c = conn.cursor()

  #populate fast lookup table:
  contactIdFromNumber = {}
  query = c.execute('SELECT _id,address FROM canonical_addresses;')
  for row in query:
    contactIdFromNumber[cleanNumber(row[1])] = row[0]

  #start the main loop through each message
  i=0
  lastSpeed=0
  lastCheckedSpeed=0
  starttime = time.time()

  for txt in texts:
    clean_number = cleanNumber(txt.number)

    #add a new canonical_addresses lookup entry and thread item if it doesn't exist
    if not clean_number in contactIdFromNumber:
      c.execute( "INSERT INTO canonical_addresses (address) VALUES (?)", [txt.number])
      contactIdFromNumber[clean_number] = c.lastrowid
      c.execute( "INSERT INTO threads (recipient_ids) VALUES (?)", [contactIdFromNumber[clean_number]])
    contact_id = contactIdFromNumber[clean_number]

    #now update the conversation thread (happends with each new message)
    c.execute( "UPDATE threads SET message_count=message_count + 1,snippet=?,'date'=? WHERE recipient_ids=? ", [txt.body,txt.date_millis,contact_id] )
    c.execute( "SELECT _id FROM threads WHERE recipient_ids=? ", [contact_id] )
    thread_id = c.fetchone()[0]

    if VERBOSE:
      print "thread_id = "+ str(thread_id)
      c.execute( "SELECT * FROM threads WHERE _id=?", [contact_id] )
      print "updated thread: " + str(c.fetchone())
      print "adding entry to message db: " + str([txt.number,txt.date_millis,txt.body,thread_id,txt.direction])

    if txt.direction == "OUT":
      dir_type = 2
    elif txt.direction == "INC":
      dir_type = 1
    else:
      print 'could not parse direction: ' + txt.direction
      quit()

    #add message to sms table
    c.execute( "INSERT INTO sms (address,date,date_sent,body,thread_id,read,type,seen) VALUES (?,?,?,?,?,?,?,?)", [
       txt.number,txt.date_millis,txt.date_sent_millis,txt.body,thread_id,1,dir_type,1])

    #print status (with fancy speed calculation)
    recalculate_every = 100
    if i%recalculate_every == 0:
      lastSpeed = int(recalculate_every/(time.time() - lastCheckedSpeed))
      lastCheckedSpeed = time.time()
    sys.stdout.write( "\rprocessed {0} entries, {1} convos, ({2} entries/sec)".format(i, len(contactIdFromNumber), lastSpeed ))
    sys.stdout.flush()
    i += 1

  print "\nfinished in {0} seconds (average {1}/second)".format((time.time() - starttime), int(i/(time.time() - starttime)))

  if VERBOSE:
    print "\n\nthreads: "
    for row in c.execute('SELECT * FROM threads'):
      print row

  if not NO_COMMIT:
    conn.commit()
    print "changes saved to "+outfile

  c.close()
  conn.close()

if __name__ == '__main__':
  sms_main()
