#' Record API responses as mock files
#'
#' `capture_requests` is a context that collects the responses from requests
#' you make and stores them as mock files. This enables you to perform a series
#' of requests against a live server once and then build your test suite using
#' those mocks, running your tests in [with_mock_api()].
#'
#' `start_capturing` and `stop_capturing` allow you to turn on/off request
#' recording for more convenient use in an interactive session.
#'
#' Recorded responses are written out as plain-text files. By storing fixtures
#' as plain-text files, you can
#' more easily confirm that your mocks look correct, and you can more easily
#' maintain them without having to re-record them. If the API changes subtly,
#' such as when adding an additional attribute to an object, you can just touch
#' up the mocks.
#'
#' If the response has status `200 OK` and the `Content-Type`
#' maps to a supported file extension---currently `.json`,
#' `.html`, `.xml`, `.txt`, `.csv`, and `.tsv`---just the response body will be
#' written out, using the appropriate extension. `204 No Content` status
#' responses will be stored as an empty file with extension `.204`. Otherwise,
#' the response will be written as a `.R` file containing syntax that, when
#' executed, recreates the
#' `httr` "response" object.
#'
#' @param expr Code to run inside the context
#' @param path Where to save the mock files. Default is the first directory in
#' [.mockPaths()], which if not otherwise specified is the current working
#' directory. It is generally better to call `.mockPaths()` directly if you
#' want to write to a different path, rather than using the `path` argument.
#' @param simplify logical: if `TRUE` (default), JSON responses with status 200
#' will be written as just the text of the response body. In all other cases,
#' and when `simplify` is `FALSE`, the "response" object will be written out to
#' a .R file using [base::dput()].
#' @param verbose logical: if `TRUE`, a `message` is printed for every file
#' that is written when capturing requests containing the absolute path of the
#' file. Useful for debugging if you're capturing but don't see the fixture
#' files being written in the expected location. Default is `FALSE`. This
#' parameter is deprecated; it is instead recommended that you set
#' `options(httptest.verbose=TRUE)` to enable.
#' @param redact function to run to purge sensitive strings from the recorded
#' response objects. This argument is deprecated: use [set_redactor()] or a
#' package redactor instead. See `vignette("redacting")` for more details.
#' @param ... Arguments passed through `capture_requests` to `start_capturing`
#' @return `capture_requests` returns the result of `expr`. `start_capturing`
#' invisibly returns the `path` it is given. `stop_capturing` returns nothing;
#' it is called for its side effects.
#' @examples
#' \dontrun{
#' capture_requests({
#'     GET("http://httpbin.org/get")
#'     GET("http://httpbin.org")
#'     GET("http://httpbin.org/response-headers",
#'         query=list(`Content-Type`="application/json"))
#' })
#' # Or:
#' start_capturing()
#' GET("http://httpbin.org/get")
#' GET("http://httpbin.org")
#' GET("http://httpbin.org/response-headers",
#'     query=list(`Content-Type`="application/json"))
#' stop_capturing()
#' }
#' @importFrom httr content
#' @export
#' @seealso [build_mock_url()] for how requests are translated to file paths
capture_requests <- function (expr, path, ...) {
    start_capturing(...)
    on.exit(stop_capturing())
    where <- parent.frame()
    if (!missing(path)) {
        with_mock_path(path, eval(expr, where))
    } else {
        eval(expr, where)
    }
}

#' @rdname capture_requests
#' @export
start_capturing <- function (path, simplify=TRUE, verbose, redact) {
    if (!missing(path)) {
        ## Note that this changes state and doesn't reset it
        .mockPaths(path)
    } else {
        path <- NULL
    }
    if (!missing(verbose)) {
        ## Note that this changes state and doesn't reset it
        warning("The 'verbose' argument to capture_requests() is deprecated; ",
            "Set options(httptest.verbose=TRUE) instead.", call.=FALSE)
        options(httptest.verbose=verbose)
    }

    if (!missing(redact)) {
        warning("The 'redact' argument to start_capturing() is deprecated. ",
            "Use 'set_redactor()' instead.", call.=FALSE)
        set_redactor(redact)
    }

    ## Use "substitute" so that args get inserted. Code remains quoted.
    req_tracer <- substitute({
        ## Get the value returned from the function, and sanitize it
        redactor <- get_current_redactor()
        .resp <- returnValue()
        if (is.null(.resp)) {
            # returnValue() defaults to NULL if the traced function exits with
            # an error, so there's no response to record.
            warning("Request errored; no captured response file saved",
                call.=FALSE)
        } else {
            save_response(redactor(.resp), simplify=simplify)
        }
    }, list(simplify=simplify))
    for (verb in c("PUT", "POST", "PATCH", "DELETE", "VERB", "GET", "RETRY")) {
        trace_httr(verb, exit=req_tracer)
    }
    invisible(path)
}

#' Write out a captured response
#'
#' @param response An 'httr' `response` object
#' @param simplify logical: if `TRUE` (default), JSON responses with status 200
#' and a supported `Content-Type`
#' will be written as just the text of the response body. In all other cases,
#' and when `simplify` is `FALSE`, the "response" object will be written out to
#' a .R file using [base::dput()].
#' @return The character file name that was written out
#' @export
#' @keywords internal
#' @importFrom jsonlite prettify
save_response <- function (response, simplify=TRUE) {
    ## Construct the mock file path
    mock_file <- buildMockURL(response$request)
    ## Track separately the actual full path we're going to write to
    dst_file <- file.path(.mockPaths()[1], mock_file)
    dir.create(dirname(dst_file), showWarnings=FALSE, recursive=TRUE)

    ## Get the Content-Type
    ct <- get_content_type(response)
    status <- response$status_code
    if (simplify && status == 200 && ct %in% names(CONTENT_TYPE_TO_EXT)) {
        ## Squelch the "No encoding supplied: defaulting to UTF-8."
        cont <- suppressMessages(content(response, "text"))
        if (ct == "application/json") {
            ## Prettify
            cont <- prettify(cont)
        }
        dst_file <- paste(dst_file, CONTENT_TYPE_TO_EXT[[ct]], sep=".")
        cat(cont, file=dst_file)
    } else if (simplify && status == 204) {
        ## "touch" a file with extension .204
        dst_file <- paste0(dst_file, ".204")
        cat("", file=dst_file)
    } else {
        ## Dump an object that can be sourced

        ## Change the file extension to .R
        dst_file <- paste0(dst_file, ".R")
        mock_file <- paste0(mock_file, ".R")

        ## If content is text, rawToChar it and dput it as charToRaw(that)
        ## so that it loads correctly but is also readable
        text_types <- c("application/json",
            "application/x-www-form-urlencoded", "application/xml",
            "text/csv", "text/html", "text/plain",
            "text/tab-separated-values", "text/xml")
        if (ct %in% text_types) {
            ## Squelch the "No encoding supplied: defaulting to UTF-8."
            cont <- suppressMessages(content(response, "text"))
            # if (ct == "application/json") {
            #     ## TODO: "parse error: premature EOF"
            #     cont <- jsonlite::prettify(cont)
            # }
            response$content <- substitute(charToRaw(cont))
        } else if (inherits(response$request$output, "write_disk")) {
            ## Copy real file and substitute the response$content "path".
            ## Note that if content is a text type, the above attempts to
            ## make the mock file readable call `content()`, which reads
            ## in the file that has been written to disk, so it effectively
            ## negates the "download" behavior for the recorded response.
            downloaded_file <- paste0(dst_file, "-FILE")
            file.copy(response$content, downloaded_file)
            mock_file <- paste0(mock_file, "-FILE")
            response$content <- substitute(structure(find_mock_file(mock_file),
                class="path"))
        }

        ## Omit curl handle C pointer, which doesn't serialize meaningfully
        response$handle <- NULL
        ## Drop request since httr:::request_perform will fill it in when loading
        response$request <- NULL

        dput(response, file=dst_file)
    }
    if (isTRUE(getOption("httptest.verbose", FALSE))) {
        message("Writing ", normalizePath(dst_file))
    }
    return(dst_file)
}

#' @rdname capture_requests
#' @export
stop_capturing <- function () {
    for (verb in c("GET", "PUT", "POST", "PATCH", "DELETE", "VERB", "RETRY")) {
        safe_untrace(verb, add_headers)
        safe_untrace(verb)
    }
}
