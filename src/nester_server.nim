import nester
import parseopt

var opts = initOptParser()
var staticPath = ""
for kind, key, value in opts.getopt():
    echo "kind ", kind, " key ", key, " value ", value
    case key
    of "p", "staticPath": staticPath = value
    else: discard

sharedRouter().serve(staticPath = staticPath)
