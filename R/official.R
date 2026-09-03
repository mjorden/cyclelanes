# Registry of municipal open-data sources ------------------------------------

.cl_registry <- new.env(parent = emptyenv())

# Denver's FACILITY_TYPE_EXISTING classes in the Denver Moves: Bikes 2025
# inventory (layer TRANS_BIKEFACILITIES_L), mapped into the package taxonomy.
# "Shared Sidewalk" and "Car-Free Street" are off-street from a cyclist's
# point of view, so they land with the separated paths; "Shared Street" is
# mixed traffic and lands with the shared lanes.
.denver_crosswalk <- c(
  "Trail"                = "separated_path",
  "Shared Sidewalk"      = "separated_path",
  "Car-Free Street"      = "separated_path",
  "Protected Bike Lane"  = "protected_lane",
  "Buffered Bike Lane"   = "buffered_lane",
  "Bike Lane"            = "painted_lane",
  "Neighborhood Bikeway" = "neighborhood_bikeway",
  "Shared Street"        = "shared_lane"
)

.builtin_sources <- function() {
  list(
    denver = list(
      city = "denver",
      label = "Denver, Colorado",
      type = "arcgis",
      # City and County of Denver's own ArcGIS organisation; the "_ODC"
      # suffix marks the Open Data Catalog publication of the layer.
      url = paste0("https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/ArcGIS/rest/services/",
                   "Denver_Bicycle_Facilities_ODC/FeatureServer/450"),
      id_field = "SEGMENT_ID",
      name_field = "STREET_NAME",
      class_field = "FACILITY_TYPE_EXISTING",
      extra_fields = c(status = "DISPLAY_STATUS",
                       proposed_class = "FACILITY_TYPE_PROPOSED",
                       from_street = "FROM_STREET",
                       to_street = "TO_STREET",
                       vertical_element = "VERTICAL_ELEMENT_TYPE",
                       core_network = "CORE_NETWORK",
                       install_year = "INSTALL_YEAR_MOST_RECENT"),
      # Future-only bikeways carry a proposed type and no existing type.
      existing_where = "FACILITY_TYPE_EXISTING IS NOT NULL",
      existing_filter = NULL,
      crosswalk = .denver_crosswalk,
      attribution = paste("City and County of Denver, Denver Moves: Bikes 2025",
                          "bikeway inventory (Denver_Bicycle_Facilities_ODC),",
                          "via the Denver Open Data Catalog."),
      homepage = "https://opendata-geospatialdenver.hub.arcgis.com/"
    )
  )
}

.all_sources <- function() {
  reg <- mget(ls(.cl_registry), envir = .cl_registry)
  builtin <- .builtin_sources()
  c(reg, builtin[setdiff(names(builtin), names(reg))])
}

.get_source <- function(city) {
  city <- tolower(trimws(city))
  src <- .all_sources()[[city]]
  if (is.null(src)) {
    rlang::abort(sprintf(
      "No official source registered for \"%s\". Known: %s. See cl_register_source().",
      city, paste(names(.all_sources()), collapse = ", ")
    ))
  }
  src
}

#' Registered official bike-facility data sources
#'
#' @return A data frame with one row per city: `city` (the key to pass to
#'   [cl_fetch_official()]), `label`, `type`, `homepage`, `attribution`.
#' @examples
#' cl_sources()
#' @export
cl_sources <- function() {
  s <- .all_sources()
  data.frame(
    city = vapply(s, `[[`, character(1), "city"),
    label = vapply(s, function(z) z$label %||% z$city, character(1)),
    type = vapply(s, `[[`, character(1), "type"),
    homepage = vapply(s, function(z) z$homepage %||% NA_character_, character(1)),
    attribution = vapply(s, function(z) z$attribution %||% NA_character_, character(1)),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

#' Register an official bike-facility source for a city
#'
#' Adds (or replaces) a source in the session registry so that
#' [cl_fetch_official(city)][cl_fetch_official] works for it. Two source
#' types are supported:
#'
#' * `"arcgis"`: `url` is an ArcGIS REST **layer** endpoint
#'   (`.../FeatureServer/<n>` or `.../MapServer/<n>`). Features are paged
#'   through the `query` operation as GeoJSON. `existing_where` is an SQL
#'   `where` clause applied server-side.
#' * `"file"`: `url` is anything [sf::st_read()] can open -- a local path or a
#'   direct URL to GeoJSON, a zipped shapefile, a GeoPackage, and so on.
#'
#' @param city Short lower-case key, e.g. `"portland"`.
#' @param url Layer endpoint or file location (see Details).
#' @param class_field Name of the attribute holding the facility class.
#' @param crosswalk Named character vector mapping each value of `class_field`
#'   to a level of [cl_facility_levels()]. Unmapped values become `none`
#'   with a warning at fetch time.
#' @param type `"arcgis"` or `"file"`.
#' @param label Human-readable name.
#' @param id_field,name_field Optional attribute names for a stable feature
#'   id and a street/route name.
#' @param extra_fields Optional named character vector: output column name
#'   = source attribute name, copied through verbatim.
#' @param existing_where For `"arcgis"` sources, an SQL where clause that
#'   restricts to built (not planned) facilities.
#' @param existing_filter A function taking the raw `sf` and returning a
#'   logical vector; applied after reading for either type.
#' @param attribution,homepage Provenance strings reported by [cl_sources()].
#' @return The registered source definition, invisibly.
#' @examples
#' cl_register_source(
#'   "exampleville",
#'   url = "https://example.org/bikeways.geojson",
#'   type = "file",
#'   class_field = "FACILITY",
#'   crosswalk = c("Protected Bike Lane" = "protected_lane",
#'                 "Bike Lane" = "painted_lane",
#'                 "Multi-Use Trail" = "separated_path")
#' )
#' cl_sources()
#' @export
cl_register_source <- function(city, url, class_field, crosswalk,
                               type = c("arcgis", "file"),
                               label = city,
                               id_field = NULL, name_field = NULL,
                               extra_fields = NULL,
                               existing_where = NULL, existing_filter = NULL,
                               attribution = NULL, homepage = NULL) {
  type <- match.arg(type)
  city <- tolower(trimws(city))
  if (!nzchar(city)) rlang::abort("`city` must be a non-empty string.")
  if (!is.character(crosswalk) || is.null(names(crosswalk)) || any(!nzchar(names(crosswalk)))) {
    rlang::abort("`crosswalk` must be a named character vector.")
  }
  bad <- setdiff(unique(crosswalk), cl_facility_levels())
  if (length(bad)) {
    rlang::abort(sprintf("`crosswalk` targets not in cl_facility_levels(): %s",
                         paste(bad, collapse = ", ")))
  }
  if (!is.null(existing_filter) && !is.function(existing_filter)) {
    rlang::abort("`existing_filter` must be a function or NULL.")
  }
  src <- list(
    city = city, label = label, type = type, url = url,
    id_field = id_field, name_field = name_field, class_field = class_field,
    extra_fields = extra_fields,
    existing_where = existing_where, existing_filter = existing_filter,
    crosswalk = crosswalk, attribution = attribution, homepage = homepage
  )
  assign(city, src, envir = .cl_registry)
  invisible(src)
}

# Fetching ---------------------------------------------------------------------

#' Fetch a city's official bike-facility inventory
#'
#' Reads the registered source for `city` (see [cl_sources()]) and returns it
#' in the same shape and taxonomy as the OpenStreetMap output, so
#' [cl_summary()] and [cl_compare()] work on either.
#'
#' @param city A key from [cl_sources()]. Default `"denver"`.
#' @param existing_only Restrict to built facilities, dropping planned or
#'   recommended ones, where the source can distinguish them.
#' @param bbox Optional WGS84 `c(xmin, ymin, xmax, ymax)` (or anything
#'   [cl_bbox()] accepts) to limit the request. Applied server-side for
#'   ArcGIS sources and after reading for file sources.
#' @param page_size Records per request for ArcGIS sources. Most services cap
#'   this at 1000 or 2000.
#' @return An `sf` in WGS84 with columns `source_id`, `name`,
#'   `official_class` (the source's own label), `facility_type` (factor over
#'   [cl_facility_levels()]), any `extra_fields` from the source definition,
#'   `length_m`, and geometry. `attr(x, "cl_source")` holds the city key and
#'   `attr(x, "cl_attribution")` the provenance string.
#' @examples
#' \dontrun{
#' den <- cl_fetch_official("denver")
#' cl_summary(den)
#' }
#' @export
cl_fetch_official <- function(city = "denver", existing_only = TRUE, bbox = NULL,
                              page_size = 2000) {
  src <- .get_source(city)
  bb <- if (!is.null(bbox)) cl_bbox(bbox) else NULL

  raw <- switch(
    src$type,
    arcgis = .arcgis_read(
      src$url,
      where = if (existing_only && !is.null(src$existing_where)) src$existing_where else "1=1",
      bbox = bb, page_size = page_size
    ),
    file = {
      z <- sf::st_read(src$url, quiet = TRUE)
      z <- sf::st_transform(z, 4326)
      if (!is.null(bb)) {
        hit <- lengths(sf::st_intersects(z, sf::st_as_sfc(sf::st_bbox(
          c(xmin = bb[["xmin"]], ymin = bb[["ymin"]], xmax = bb[["xmax"]], ymax = bb[["ymax"]]),
          crs = sf::st_crs(4326))))) > 0
        z <- z[hit, ]
      }
      z
    },
    rlang::abort(sprintf("Unknown source type \"%s\".", src$type))
  )

  if (existing_only && is.function(src$existing_filter) && nrow(raw) > 0) {
    keep <- src$existing_filter(raw)
    raw <- raw[keep %in% TRUE, ]
  }

  out <- .standardise_official(raw, src)
  attr(out, "cl_source") <- src$city
  attr(out, "cl_attribution") <- src$attribution
  attr(out, "cl_fetched") <- Sys.time()
  out
}

# Convert a raw official layer into the package's standard columns.
.standardise_official <- function(raw, src) {
  .stop_if_not_sf(raw, "raw")
  n <- nrow(raw)
  get <- function(field) {
    if (is.null(field) || !field %in% names(raw)) return(rep(NA_character_, n))
    as.character(raw[[field]])
  }
  if (!src$class_field %in% names(raw)) {
    rlang::abort(sprintf("Source \"%s\": class field \"%s\" not found in the data (have: %s).",
                         src$city, src$class_field,
                         paste(setdiff(names(raw), attr(raw, "sf_column")), collapse = ", ")))
  }
  official_class <- get(src$class_field)
  facility <- .apply_crosswalk(official_class, src$crosswalk, src$city)

  d <- data.frame(
    source_id = if (is.null(src$id_field)) as.character(seq_len(n)) else get(src$id_field),
    name = get(src$name_field),
    official_class = official_class,
    facility_type = .facility_factor(facility),
    stringsAsFactors = FALSE
  )
  for (nm in names(src$extra_fields)) d[[nm]] <- get(src$extra_fields[[nm]])

  geom <- sf::st_geometry(raw)
  if (is.na(sf::st_crs(geom))) sf::st_crs(geom) <- 4326
  geom <- sf::st_transform(geom, 4326)
  out <- sf::st_sf(d, geometry = geom)
  out$length_m <- .length_m(out)
  rownames(out) <- NULL
  out
}

.apply_crosswalk <- function(class, crosswalk, city = "source") {
  out <- unname(crosswalk[class])
  unmapped <- unique(class[!is.na(class) & is.na(out)])
  if (length(unmapped)) {
    rlang::warn(sprintf(
      "%s: %d class value(s) not in the crosswalk were set to \"none\": %s",
      city, length(unmapped), paste(shQuote(unmapped), collapse = ", ")
    ))
  }
  out[is.na(out)] <- "none"
  out
}

# Page through an ArcGIS REST layer's query endpoint as GeoJSON.
.arcgis_read <- function(layer_url, where = "1=1", bbox = NULL, page_size = 2000,
                         out_fields = "*") {
  base <- sub("/+$", "", layer_url)
  offset <- 0L
  pieces <- list()
  repeat {
    params <- list(
      where = where, outFields = out_fields, outSR = 4326, f = "geojson",
      resultOffset = offset, resultRecordCount = page_size
    )
    if (!is.null(bbox)) {
      params$geometry <- paste(bbox, collapse = ",")
      params$geometryType <- "esriGeometryEnvelope"
      params$inSR <- 4326
      params$spatialRel <- "esriSpatialRelIntersects"
    }
    url <- paste0(base, "/query?", .query_string(params))
    tmp <- tempfile(fileext = ".geojson")
    on.exit(unlink(tmp), add = TRUE)
    status <- tryCatch(utils::download.file(url, tmp, quiet = TRUE, mode = "wb"),
                       error = function(e) -1L)
    if (!identical(as.integer(status), 0L)) {
      rlang::abort(sprintf("Request to %s failed.", base))
    }
    head <- readChar(tmp, nchars = min(2000L, file.info(tmp)$size), useBytes = TRUE)
    if (grepl("^\\s*\\{\\s*\"error\"", head)) {
      rlang::abort(sprintf("ArcGIS service returned an error: %s", substr(head, 1, 300)))
    }
    if (grepl("\"features\"\\s*:\\s*\\[\\s*\\]", head)) break

    part <- sf::st_read(tmp, quiet = TRUE)
    pieces[[length(pieces) + 1L]] <- part
    if (nrow(part) < page_size) break
    offset <- offset + page_size
  }
  if (!length(pieces)) {
    return(sf::st_sf(data.frame(), geometry = sf::st_sfc(crs = 4326)))
  }
  out <- do.call(rbind, pieces)
  rownames(out) <- NULL
  out
}

`%||%` <- function(a, b) if (is.null(a)) b else a
