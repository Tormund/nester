import nester
import cligen

proc run(address:string = "", port: int = 5000, staticPath: string = "."): int =
    var router = newRouter()
    router.serve(address = address, p = Port(port), staticPath = staticPath)

dispatch(run)
