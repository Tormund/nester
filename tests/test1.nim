
import nester

let router = newRouter()
router.routes:
    get "/": resp(Http200, "OK")

router.serve()
