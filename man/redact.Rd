% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/redact.R
\name{redact_cookies}
\alias{redact_cookies}
\alias{redact_headers}
\alias{within_body_text}
\alias{redact}
\alias{redact_auth}
\alias{redact_cookies}
\alias{redact_headers}
\alias{within_body_text}
\title{Remove sensitive content from HTTP responses}
\usage{
redact_cookies(response)

redact_headers(response, headers = c())

within_body_text(response, FUN)

redact_auth(response)
}
\arguments{
\item{response}{An 'httr' \code{response} object to sanitize.}

\item{headers}{For \code{redact_headers()}, a character vector of header names to
sanitize. Note that \code{redact_headers()} itself does not do redacting but
returns a function that when called does the redacting.}

\item{FUN}{For \code{within_body_text()}, a function that takes as its argument a
character vector and returns a modified version of that. This function will
be applied to the text of the response's "content".}
}
\value{
All redacting functions return a well-formed 'httr' \code{response}
object.
}
\description{
When recording requests for use as test fixtures, you don't want to include
secrets like authentication tokens and personal ids. These functions provide
a means for redacting this kind of content, or anything you want, from
responses that \code{\link[=capture_requests]{capture_requests()}} saves.
}
\details{
\code{redact_cookies()} removes cookies from 'httr' \code{response} objects.
\code{redact_headers()} lets you target selected request and response headers for
redaction. \code{redact_auth()} is a convenience wrapper around
them for a useful default redactor in \code{capture_requests()}.

\code{within_body_text()} lets you manipulate the text of the response body
and manages the parsing of the raw (binary) data in the 'response' object.
}
\seealso{
\code{vignette("redacting", package="httptest")} for a detailed discussion of what these functions do and how to customize them. \code{\link[=gsub_response]{gsub_response()}} is another redactor.
}
