#' Check a registered source's crosswalk against the live layer
#'
#' Cities rename and add facility classes. A value missing from the
#' crosswalk silently becomes `none`. This fetches the distinct values of
#' the class field as they are today and reports which are mapped, which
#' are new (`unmapped`), and which crosswalk keys no longer occur
#' (`stale`). Run it before trusting a summary, and see the
#' `check-sources` workflow for a weekly automated run.
#'
#' @param city A key from [cl_sources()].
#' @param sample For ArcGIS layers that cannot return distinct values,
#'   how many rows to sample instead.
#' @return A data frame of class `cl_source_check` with columns `value`,
#'   `status` (`mapped`, `unmapped`, `stale`), `target` (the taxonomy level
#'   for mapped and stale rows) and `n` (feature count where the server
#'   reports it). `attr(x, "ok")` is `TRUE` when nothing is unmapped, and
#'   `attr(x, "city")` names the source.
#' @examples
#' \dontrun{
#' cl_check_source("denver")
#' cl_check_source("austin")
#' }
#' @export
cl_check_source <- function(city, sample = 5000) {
  src <- .get_source(city)
  live <- switch(
    src$type,
    arcgis = .distinct_arcgis(src$url, src$class_field, sample),
    file = {
      x <- sf::st_read(src$url, quiet = TRUE)
      if (!src$class_field %in% names(x)) {
        rlang::abort(sprintf("Source \"%s\": class field \"%s\" not in the data.", src$city, src$class_field))
      }
      v <- trimws(as.character(x[[src$class_field]]))
      v <- v[!is.na(v) & nzchar(v)]
      tab <- table(v)
      data.frame(value = names(tab), n = as.integer(tab), stringsAsFactors = FALSE)
    },
    rlang::abort(sprintf("Unknown source type \"%s\".", src$type))
  )
  keys <- names(src$crosswalk)
  mapped <- live$value %in% keys
  rows <- data.frame(
    value = live$value,
    status = ifelse(mapped, "mapped", "unmapped"),
    target = ifelse(mapped, unname(src$crosswalk[live$value]), NA_character_),
    n = live$n,
    stringsAsFactors = FALSE
  )
  stale <- setdiff(keys, live$value)
  if (length(stale)) {
    rows <- rbind(rows, data.frame(value = stale, status = "stale",
                                   target = unname(src$crosswalk[stale]), n = 0L,
                                   stringsAsFactors = FALSE))
  }
  rows <- rows[order(match(rows$status, c("unmapped", "mapped", "stale")), -rows$n, rows$value), ]
  rownames(rows) <- NULL
  structure(rows, class = c("cl_source_check", "data.frame"),
            city = src$city, ok = !any(rows$status == "unmapped"))
}

# Distinct values of one field from an ArcGIS layer. Uses
# returnDistinctValues where the server honours it (AGOL does), otherwise
# tabulates a sample.
.distinct_arcgis <- function(layer_url, field, sample) {
  base <- sub("/+$", "", layer_url)
  tmp <- .arcgis_get(paste0(base, "/query?", .query_string(list(
    where = paste0(field, " IS NOT NULL"), outFields = field, returnGeometry = "false",
    returnDistinctValues = "true", orderByFields = field, f = "json"))))
  on.exit(unlink(tmp), add = TRUE)
  txt <- readLines(tmp, warn = FALSE, encoding = "UTF-8")
  .arcgis_check_error(paste(txt, collapse = ""), "distinct values")
  js <- tryCatch(jsonlite::fromJSON(paste(txt, collapse = "\n"), simplifyVector = TRUE), error = function(e) NULL)
  attrs <- js$features$attributes
  vals <- if (is.data.frame(attrs) && field %in% names(attrs)) attrs[[field]] else character()
  vals <- trimws(as.character(vals))
  vals <- unique(vals[!is.na(vals) & nzchar(vals)])

  # counts per value, one cheap request each; skip if the server refused distincts
  counts <- rep(NA_integer_, length(vals))
  if (length(vals) && length(vals) <= 50) {
    for (i in seq_along(vals)) {
      w <- sprintf("%s = '%s'", field, gsub("'", "''", vals[i]))
      t2 <- .arcgis_get(paste0(base, "/query?", .query_string(list(where = w, returnCountOnly = "true", f = "json"))))
      c2 <- tryCatch(jsonlite::fromJSON(readLines(t2, warn = FALSE, encoding = "UTF-8")), error = function(e) NULL)
      unlink(t2)
      counts[i] <- as.integer(c2$count %||% NA_integer_)
    }
  }
  if (!length(vals)) {
    # fall back to a sample
    t3 <- .arcgis_get(paste0(base, "/query?", .query_string(list(
      where = "1=1", outFields = field, returnGeometry = "false",
      resultRecordCount = sample, f = "json"))))
    on.exit(unlink(t3), add = TRUE)
    js3 <- tryCatch(jsonlite::fromJSON(readLines(t3, warn = FALSE, encoding = "UTF-8"), simplifyVector = TRUE), error = function(e) NULL)
    a3 <- js3$features$attributes
    v3 <- if (is.data.frame(a3) && field %in% names(a3)) trimws(as.character(a3[[field]])) else character()
    v3 <- v3[!is.na(v3) & nzchar(v3)]
    tab <- table(v3)
    vals <- names(tab)
    counts <- as.integer(tab)
  }
  data.frame(value = vals, n = counts, stringsAsFactors = FALSE)
}

#' @export
print.cl_source_check <- function(x, ...) {
  city <- attr(x, "city")
  n_un <- sum(x$status == "unmapped")
  n_st <- sum(x$status == "stale")
  cat(sprintf("<cl_source_check> %s: %s\n", city,
              if (isTRUE(attr(x, "ok"))) "crosswalk covers every live class" else
                sprintf("%d unmapped class %s", n_un, if (n_un == 1) "value" else "values")))
  if (n_st) cat(sprintf("  %d crosswalk key%s no longer occur%s in the data\n",
                        n_st, if (n_st == 1) "" else "s", if (n_st == 1) "s" else ""))
  d <- as.data.frame(unclass(x), stringsAsFactors = FALSE)
  d$target[is.na(d$target)] <- ""
  d$n[is.na(d$n)] <- NA
  print(d, row.names = FALSE, na.print = "")
  invisible(x)
}
