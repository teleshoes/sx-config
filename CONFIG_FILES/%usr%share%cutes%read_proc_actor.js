function readProc(cmdArr) {
  var cmdExec = cmdArr[0];
  var cmdArgs = cmdArr.slice(1);

  var proc = cutes.require('subprocess').process();
  var res = proc.popen_sync(cmdExec, cmdArgs);
  res.wait(-1);
  return res.stdout().toString();
}

exports = function(cmdStr, ctx) {
  return readProc(["sh", "-c", cmdStr])
}

