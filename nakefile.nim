import nake

var
  buildArtifacts = @["nimcache", "tests/nimcache", "tests/t1"]
  #buildFlags = "-d:release --verbosity:1 --hints:off --warnings:off --threads:on --embedsrc --lineDir:on"
  buildFlags = "-d:release --verbosity:3 --hints:off --warnings:on --threads:on --embedsrc --lineDir:on --parallelBuild:1"

  docFlags = ""
  docFiles: seq[string] = @[]
  exampleFiles: seq[string] = @[]

task defaultTask, "Clean, Compile and run the tests":
  runTask "clean"
  runTask "docs"
  runTask "build-tests"
  runTask "run-tests"

task "docs", "Buiild the documents":
  for file in docFiles:
    if not shell(nimExe, "doc", docFlags, file):
      echo "error generating docs"
      quit 1

task "exmpl", "Build and run the exmpl":
  for file in exampleFiles:
    echo "file=", file
    if not shell(nimExe, "c -r",  buildFlags, file):
      echo "error compiling"
      quit 1

task "build-tests", "Build the tests":
  if not shell(nimExe, "c",  buildFlags, "tests/t1.nim"):
    echo "error compiling"
    quit 1

task "run-tests", "Run the tests":
  discard shell("tests/t1")

task "clean", "clean build artifacts":
  proc removeFileOrDir(file) =
    try:
      removeFile(file)
    except OSError:
      try:
        removeDir(file)
      except OSError:
        echo "Could not remove: ", file, " ", getCurrentExceptionMsg()

  for file in buildArtifacts:
    removeFileOrDir(file)

