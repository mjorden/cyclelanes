# Clip a line layer to a polygon boundary. Ways crossing the boundary are
# cut at it, not dropped; ways outside are removed. Attributes are carried
# through unchanged and `length_m`, if present, is recomputed.
.clip_lines <- function(x, boundary) {
  .stop_if_not_sf(x)
  if (nrow(x) == 0L) return(x)
  b <- sf::st_union(sf::st_geometry(boundary))
  if (!all(sf::st_geometry_type(b) %in% c("POLYGON", "MULTIPOLYGON"))) {
    rlang::abort("`boundary` must be a polygon.")
  }
  crs_in <- sf::st_crs(x)
  crs_work <- .utm_crs(x)
  xw <- sf::st_transform(x, crs_work)
  bw <- sf::st_transform(b, crs_work)
  sf::st_agr(xw) <- "constant"

  # cheap prefilter, then exact cut for the ones that cross
  inside <- lengths(sf::st_covered_by(xw, bw)) > 0
  touches <- lengths(sf::st_intersects(xw, bw)) > 0
  keep <- xw[inside, ]
  cross <- xw[touches & !inside, ]
  if (nrow(cross) > 0L) {
    cut <- suppressWarnings(sf::st_intersection(cross, bw))
    if (nrow(cut) > 0L) {
      # a way touching the boundary at a point, or a mixed result, needs the
      # line parts pulled out; a way cut into pieces is a MULTILINESTRING
      types <- as.character(sf::st_geometry_type(cut))
      if (any(types == "GEOMETRYCOLLECTION")) {
        cut <- suppressWarnings(sf::st_collection_extract(cut, "LINESTRING"))
        types <- as.character(sf::st_geometry_type(cut))
      }
      cut <- cut[types %in% c("LINESTRING", "MULTILINESTRING"), ]
      cut <- cut[!sf::st_is_empty(cut), ]
      if (nrow(cut) > 0L) keep <- rbind(keep, cut)
    }
  }
  out <- sf::st_transform(keep, crs_in)
  if ("length_m" %in% names(out)) out$length_m <- .length_m(out)
  rownames(out) <- NULL
  out
}
