import nester
import cligen

proc run(port: int = 5000, staticPath: string = "."): int =
    var router = newRouter()
    router.serve(p = Port(port), staticPath = staticPath)

dispatch(run)
