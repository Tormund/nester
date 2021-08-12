import nest
import
    strutils, tables, oids, os, times, md5, strtabs,
    asynchttpserver, asyncdispatch, asyncfile, asyncnet,
    httpcore, cookies, mimetypes, uri

export
    asynchttpserver, strtabs, map, HttpMethod, asyncdispatch

type
    Handler = proc(r: Request, args: RoutingArgs): Future[void] {.gcsafe.}
    NesterRouter* = ref object
        nestRouter: Router[Handler]
        routesRegistry: Table[string, HttpMethod]
        staticPath: string
        httpServer: AsyncHttpServer

proc newRouter*(): NesterRouter =
    result.new()
    result.nestRouter = nest.newRouter[Handler]()
    result.routesRegistry = initTable[string, HttpMethod]()

var gRouter {.threadVar.}: NesterRouter
proc sharedRouter*(): NesterRouter =
    if gRouter.isNil:
        gRouter = newRouter()
    gRouter

template map(router: Router, action: string, path: string, handler: untyped) =
    block:
        proc handleRoute(r: Request, args: RoutingArgs) {.async.} =
            template request: Request {.inject, used.} = r
            var parms: StringTableRef
            template params(r: Request): StringTableRef {.inject, used.} =
                args.queryArgs

            template `@`(a: string): string {.inject, used.} =
                args.pathArgs[a]
            handler

        router.map(handleRoute, action, path)

template get*(router: Router, path: string, body: untyped) =
    map(router, "get", path, body)

template post*(router: Router, path: string, body: untyped) =
    map(router, "post", path, body)

template resp*(code: HttpCode,
               headers: openarray[tuple[key, val: string]],
               content: string) =
    echo "< \n", indent(content, 4)
    yield request.respond(code, content, newHttpHeaders(headers))

template resp*(code: HttpCode, content: string,
               contentType = "text/html;charset=utf-8") =
    resp(code, {
        "Access-Control-Allow-Origin": "*",
        "Content-Type": contentType
        },
        content
    )

template redirect*(url: string) =
    resp(Http303, [(key: "Location", val: url)], "")

template routes*(router: NesterRouter, body: untyped) =
    template get(path: string, b: untyped) {.inject.} =
        router.nestRouter.get(path, b)
        router.routesRegistry[path] = HttpMethod.HttpGet

    template post(path: string, b: untyped) {.inject.} =
        router.nestRouter.post(path, b)
        router.routesRegistry[path] = HttpMethod.HttpPost

    body

proc cookies*(r: Request): StringTableRef =
    if (let cookie = r.headers.getOrDefault("Cookie"); cookie != ""):
        result = parseCookies(cookie)
    else:
        result = newStringTable()

converter toStringEx*(values: HttpHeaderValues): string =
    return seq[string](values).join(",")

proc allowCrossOriginRequests(r: Request) {.async.} =
    let headers = newHttpHeaders({
        "Access-Control-Allow-Origin" : "*",
        "Access-Control-Allow-Headers" : r.headers["Access-Control-Request-Headers"].toStringEx(),
        "Access-Control-Allow-Methods": r.headers["Access-Control-Request-Method"].toStringEx()
    })
    await r.respond(Http200, "", headers)

const CL = "\c\L"
template rawPresendFile(request: Request, file: string): Future[void] =
    var msg = "HTTP/1.1 " & $Http200 & CL

    msg.add("Content-Type: " & newMimetypes().getMimetype(file.splitFile.ext[1..^1]))
    msg.add(CL)

    msg.add("Content-Length: " & $getFileSize(file))
    msg.add(CL)

    msg.add(CL) # headers end
    msg.add("") # content
    request.client.send(msg)

proc sendFile(r: NesterRouter, request: Request, file: string) {.async.} =
    var fp = getFilePermissions(file)
    if not fp.contains(fpOthersRead):
        resp(Http403, "No permissions. Fix this!")
    else:
        await request.rawPresendFile(file)

        let file = openAsync(file, fmRead)
        const packsz = 4096
        var value = await file.read(packsz)
        while value.len > 0:
            await request.client.send(value)
            value = await file.read(packsz)
        file.close()

proc startServer(r: NesterRouter, p: Port, cb: proc(request: Request): Future[void] {.gcsafe.} ) {.async.} =
    try:
        await r.httpServer.serve(p, cb)
    except:
        echo "Exception caught in server: ", getCurrentExceptionMsg()
        echo getCurrentException().getStackTrace()

    try:
        r.httpServer.close()
    except:
        echo "Exception caught while closing server: ", getCurrentExceptionMsg()
        echo getCurrentException().getStackTrace()

proc serve*(r: NesterRouter, p: Port = Port(5000), staticPath: string = "") =
    echo "serving nester "
    if "/" notin r.routesRegistry:
        echo "set nester default redirect "
        r.routes:
            get "/": redirect "index.html"

    r.nestRouter.compress()
    r.staticPath = staticPath

    r.httpServer = newAsyncHttpServer()

    echo "Nester started 127.0.0.1:", $(p.uint16)
    echo "Nester serves ", r.routesRegistry

    asyncCheck startServer(r, p) do(request: Request) {.async, gcsafe.}:
        try:
            if request.reqMethod == HttpOptions:
                await allowCrossOriginRequests(request)
            else:

                echo "> ", request.url.path, "\n", indent(request.body, 4)

                let res = r.nestRouter.route($request.reqMethod, request.url, request.headers)
                let t0 = epochTime()

                if res.status == routingFailure and $request.url notin r.routesRegistry and request.reqMethod == HttpMethod.HttpGet:
                    let p = r.staticPath / request.url.path
                    if fileExists(p):
                        await r.sendFile(request, p)
                    else:
                        resp(Http404, "Resource not found")
                elif res.status == routingFailure:
                    resp(Http404, "Resource not found")
                else:
                    var ok = false
                    var requestId: string
                    try:
                        await res.handler(request, res.arguments)
                        ok = true
                    except:
                        requestId = $genOid()
                        echo "Exception caught(", requestId, "): ", getCurrentExceptionMsg()
                        echo getCurrentException().getStackTrace()

                    if not ok:
                        if requestId.len > 0:
                            requestId = " Request id: " & requestId
                        else:
                            requestId = ""
                        resp(Http500, "Internal server error." & requestId)

                echo ">~", request.url.path, " in ", formatFloat(epochTime() - t0, format = ffDecimal, precision = 3), "s"
        except Exception as e:
            echo "Invalid request ", request.url, " ", request.body
            echo e.msg
            echo getStackTrace(e)

    let timeout = 500
    while true:
        if hasPendingOperations(): # avoid ValueError in case no operations are pending
            drain(timeout = timeout)
