import nester
import cligen

proc start(port: int = 5000, staticPath: string = ".")=
    var router = newRouter()
    router.serve(p = Port(port), staticPath = staticPath)

dispatch(start)
