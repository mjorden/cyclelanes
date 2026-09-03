# Regenerate the `denver_lodo` dataset: a raw Overpass result and the city's
# official inventory for a small box over downtown Denver (Cherry Creek
# trail, 15th/16th Street lanes, Union Station). Run from the package root:
#
#   Rscript data-raw/denver_lodo.R
#
# Needs network access. The fetch date is recorded in the object and must be
# updated in R/data.R when this is re-run.

devtools::load_all(".", quiet = TRUE)

box <- c(-105.005, 39.740, -104.985, 39.752)
# Both layers are cut at the box edge, so long trails that merely pass
# through do not dominate the lengths.
box_poly <- sf::st_as_sfc(sf::st_bbox(
  c(xmin = box[1], ymin = box[2], xmax = box[3], ymax = box[4]), crs = sf::st_crs(4326)))

osm <- cl_fetch_osm(box, clip = box_poly, retries = 4)
official <- cl_fetch_official("denver", bbox = sf::st_sf(geometry = box_poly))

# Keep the fixture small: drop tag columns that are NA for every way, and
# round coordinates to ~10 cm.
keep <- vapply(sf::st_drop_geometry(osm), function(col) any(!is.na(col)), logical(1))
osm <- osm[, names(keep)[keep]]
sf::st_geometry(osm) <- sf::st_set_precision(sf::st_geometry(osm), 1e6)
sf::st_geometry(official) <- sf::st_set_precision(sf::st_geometry(official), 1e6)
for (a in c("cl_bbox", "cl_boundary", "cl_fetched")) attr(osm, a) <- NULL
for (a in c("cl_boundary", "cl_fetched")) attr(official, a) <- NULL
rownames(osm) <- NULL
rownames(official) <- NULL

denver_lodo <- list(
  osm = osm,
  official = official,
  bbox = cl_bbox(box),
  fetched = as.Date(Sys.time())
)

cat(sprintf("osm: %d ways, %d columns; official: %d segments; fetched %s\n",
            nrow(osm), ncol(osm), nrow(official), denver_lodo$fetched))

usethis_save <- function(obj, name) {
  dir.create("data", showWarnings = FALSE)
  assign(name, obj)
  save(list = name, file = file.path("data", paste0(name, ".rda")), compress = "xz", version = 2)
}
usethis_save(denver_lodo, "denver_lodo")
cat(sprintf("data/denver_lodo.rda: %.0f kB\n", file.info("data/denver_lodo.rda")$size / 1024))
