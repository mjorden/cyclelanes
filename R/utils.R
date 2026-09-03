# Internal helpers ------------------------------------------------------------

# Add any missing columns as NA character so tag lookups never fail.
.ensure_cols <- function(df, cols) {
  for (col in setdiff(cols, names(df))) df[[col]] <- NA_character_
  df
}

# Lower-case, trimmed, NA-safe tag value. Empty strings become NA.
.norm_tag <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x[!is.na(x) & !nzchar(x)] <- NA_character_
  x
}

# TRUE where a tag is present and is not an explicit negative.
.tag_truthy <- function(x) {
  x <- .norm_tag(x)
  !is.na(x) & !x %in% c("no", "none", "0", "false")
}

# A projected CRS suitable for metric buffering: the UTM zone of the centroid.
.utm_crs <- function(x) {
  bb <- sf::st_bbox(sf::st_transform(sf::st_geometry(x), 4326))
  lon <- mean(c(bb[["xmin"]], bb[["xmax"]]))
  lat <- mean(c(bb[["ymin"]], bb[["ymax"]]))
  zone <- floor((lon + 180) / 6) + 1
  zone <- max(1, min(60, zone))
  sf::st_crs(if (lat >= 0) 32600 + zone else 32700 + zone)
}

# Length in metres as a plain numeric vector (geodesic for lon/lat inputs).
.length_m <- function(x) {
  as.numeric(units::set_units(sf::st_length(x), "m"))
}

.stop_if_not_sf <- function(x, arg = "x") {
  if (!inherits(x, "sf")) {
    rlang::abort(sprintf("`%s` must be an sf object.", arg))
  }
  invisible(x)
}

# Percent-encode a named list into a URL query string.
.query_string <- function(params) {
  vals <- vapply(params, function(v) utils::URLencode(as.character(v), reserved = TRUE),
                 character(1))
  paste(names(params), vals, sep = "=", collapse = "&")
}
