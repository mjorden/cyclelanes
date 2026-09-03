#' Look at a candidate official layer before registering it
#'
#' Building a crosswalk for a new city means finding the attribute that
#' holds the facility class and enumerating its values. This does that in
#' one call, and prints where the layer's extent sits so a wrong-city layer
#' is obvious before any crosswalk is written.
#'
#' @param url An ArcGIS REST layer endpoint (`.../FeatureServer/<n>`) or
#'   anything [sf::st_read()] can open.
#' @param type `"arcgis"` or `"file"`. Guessed from `url` when omitted.
#' @param max_values Only string fields with at most this many distinct
#'   values get a frequency table; the rest report their distinct count.
#' @param sample For ArcGIS layers, how many rows to fetch (attributes
#'   only, no geometry) to tabulate values from. Layers with more rows than
#'   this are sampled, and the print method says so.
#' @return A list of class `cl_source_inspection`: `url`, `type`, `name`,
#'   `n` (feature count), `geometry_type`, `crs` (EPSG code where known),
#'   `max_record_count`, `fields` (a data frame of name / type / alias),
#'   `values` (a named list of frequency tables), `n_sampled`, and `extent`
#'   (WGS84 `c(xmin, ymin, xmax, ymax)`) with `centre`.
#' @examples
#' \dontrun{
#' cl_inspect_source(
#'   "https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/ArcGIS/rest/services/Denver_Bicycle_Facilities_ODC/FeatureServer/450"
#' )
#' }
#' @export
cl_inspect_source <- function(url, type = NULL, max_values = 30, sample = 2000) {
  if (!is.character(url) || length(url) != 1L) rlang::abort("`url` must be a single string.")
  if (is.null(type)) {
    type <- if (grepl("/(Feature|Map)Server/[0-9]+/?$", url)) "arcgis" else "file"
  }
  type <- match.arg(type, c("arcgis", "file"))
  out <- if (type == "arcgis") .inspect_arcgis(url, max_values, sample) else .inspect_file(url, max_values)
  out$url <- url
  out$type <- type
  structure(out, class = "cl_source_inspection")
}

.inspect_arcgis <- function(url, max_values, sample) {
  base <- sub("/+$", "", url)
  info <- .arcgis_layer_info(base)

  tmp <- .arcgis_get(paste0(base, "/query?", .query_string(list(where = "1=1", returnCountOnly = "true", f = "json"))))
  on.exit(unlink(tmp), add = TRUE)
  cnt <- tryCatch(jsonlite::fromJSON(readLines(tmp, warn = FALSE, encoding = "UTF-8")), error = function(e) NULL)
  n <- as.integer(cnt$count %||% NA_integer_)

  str_fields <- info$fields$name[info$fields$type %in% "String"]
  values <- list()
  n_sampled <- 0L
  if (length(str_fields)) {
    page <- max(1L, min(as.integer(sample), info$max_record_count))
    tmp2 <- .arcgis_get(paste0(base, "/query?", .query_string(list(
      where = "1=1", outFields = paste(str_fields, collapse = ","),
      returnGeometry = "false", resultRecordCount = page, f = "json"))))
    on.exit(unlink(tmp2), add = TRUE)
    js <- tryCatch(jsonlite::fromJSON(readLines(tmp2, warn = FALSE, encoding = "UTF-8"), simplifyVector = TRUE),
                   error = function(e) NULL)
    attrs <- js$features$attributes
    if (is.data.frame(attrs) && nrow(attrs)) {
      n_sampled <- nrow(attrs)
      values <- .tabulate_values(attrs, max_values)
    }
  }

  extent <- NULL
  centre <- NULL
  if (!is.null(info$extent) && !is.na(info$wkid)) {
    ext <- tryCatch({
      b <- sf::st_bbox(info$extent, crs = sf::st_crs(as.integer(info$wkid)))
      sf::st_bbox(sf::st_transform(sf::st_as_sfc(b), 4326))
    }, error = function(e) NULL)
    if (!is.null(ext)) {
      extent <- stats::setNames(as.numeric(ext), c("xmin", "ymin", "xmax", "ymax"))
      centre <- c(lon = mean(extent[c("xmin", "xmax")]), lat = mean(extent[c("ymin", "ymax")]))
    }
  }

  list(
    name = info$name, n = n, geometry_type = sub("^esriGeometry", "", info$geometry_type),
    crs = as.integer(info$wkid), max_record_count = info$max_record_count,
    fields = info$fields, values = values, n_sampled = n_sampled,
    extent = extent, centre = centre
  )
}

.inspect_file <- function(url, max_values) {
  x <- sf::st_read(url, quiet = TRUE)
  d <- sf::st_drop_geometry(x)
  fields <- data.frame(
    name = names(d),
    type = vapply(d, function(col) class(col)[1], character(1)),
    alias = NA_character_,
    stringsAsFactors = FALSE
  )
  is_str <- vapply(d, function(col) is.character(col) || is.factor(col), logical(1))
  values <- if (any(is_str)) .tabulate_values(d[, is_str, drop = FALSE], max_values) else list()
  crs <- sf::st_crs(x)$epsg
  extent <- NULL
  centre <- NULL
  if (nrow(x) && !is.na(sf::st_crs(x))) {
    ext <- sf::st_bbox(sf::st_transform(x, 4326))
    extent <- stats::setNames(as.numeric(ext), c("xmin", "ymin", "xmax", "ymax"))
    centre <- c(lon = mean(extent[c("xmin", "xmax")]), lat = mean(extent[c("ymin", "ymax")]))
  }
  list(
    name = basename(url), n = nrow(x),
    geometry_type = as.character(unique(sf::st_geometry_type(x)))[1],
    crs = if (is.null(crs)) NA_integer_ else as.integer(crs), max_record_count = NA_integer_,
    fields = fields, values = values, n_sampled = nrow(x), extent = extent, centre = centre
  )
}

# Frequency tables for short string columns; a distinct count for long ones.
.tabulate_values <- function(d, max_values) {
  out <- list()
  for (nm in names(d)) {
    v <- trimws(as.character(d[[nm]]))
    v[!is.na(v) & !nzchar(v)] <- NA_character_
    nd <- length(unique(v[!is.na(v)]))
    if (nd == 0) next
    if (nd <= max_values) {
      tab <- sort(table(v, useNA = "ifany"), decreasing = TRUE)
      out[[nm]] <- stats::setNames(as.integer(tab), ifelse(is.na(names(tab)), "<NA>", names(tab)))
    } else {
      out[[nm]] <- structure(nd, class = "cl_distinct_count")
    }
  }
  out
}

#' @export
print.cl_source_inspection <- function(x, ...) {
  cat(sprintf("<cl_source_inspection> %s (%s)\n", x$name, x$type))
  cat(sprintf("  %s\n", x$url))
  cat(sprintf("  %s features, %s, EPSG:%s%s\n",
              format(x$n, big.mark = ","), x$geometry_type %||% "?", x$crs %||% "?",
              if (!is.na(x$max_record_count %||% NA)) sprintf(", max %d per page", x$max_record_count) else ""))
  if (!is.null(x$centre)) {
    cat(sprintf("  extent centre: lon %.3f, lat %.3f  <- check this is the city you expect\n",
                x$centre[["lon"]], x$centre[["lat"]]))
  } else {
    cat("  extent: unknown\n")
  }
  cat(sprintf("\nFields (%d):\n", nrow(x$fields)))
  f <- x$fields
  for (i in seq_len(nrow(f))) {
    cat(sprintf("  %-32s %-12s %s\n", f$name[i], f$type[i], if (is.na(f$alias[i])) "" else f$alias[i]))
  }
  if (length(x$values)) {
    cat(sprintf("\nValues%s:\n",
                if (!is.na(x$n) && x$n_sampled < x$n) sprintf(" (from a sample of %d rows)", x$n_sampled) else ""))
    for (nm in names(x$values)) {
      v <- x$values[[nm]]
      if (inherits(v, "cl_distinct_count")) {
        cat(sprintf("  %s: %d distinct values\n", nm, as.integer(v)))
      } else {
        cat(sprintf("  %s:\n", nm))
        for (i in seq_along(v)) cat(sprintf("    %6d  %s\n", v[[i]], names(v)[i]))
      }
    }
  }
  invisible(x)
}
