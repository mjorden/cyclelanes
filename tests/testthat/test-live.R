# Network tests against the public Overpass, Nominatim and Denver ArcGIS
# services. They are opt-in -- set CYCLELANES_LIVE_TESTS=true -- so that CI
# and casual local runs never fail on a shared server's rate limit or a
# 504. A small box over downtown Denver (Cherry Creek trail, 15th St lanes).
denver_box <- c(-105.005, 39.740, -104.985, 39.752)

skip_unless_live <- function(host) {
  skip_on_cran()
  if (!identical(tolower(Sys.getenv("CYCLELANES_LIVE_TESTS")), "true")) {
    skip("live tests are opt-in: set CYCLELANES_LIVE_TESTS=true")
  }
  skip_if_offline(host)
}

test_that("live: OSM fetch + classify returns facilities in downtown Denver", {
  skip_unless_live("overpass-api.de")

  raw <- cl_fetch_osm(denver_box, timeout = 120)
  expect_s3_class(raw, "sf")
  expect_gt(nrow(raw), 0)
  expect_equal(attr(raw, "cl_bbox"), cl_bbox(denver_box))

  lanes <- cl_classify(raw, drop_none = TRUE)
  expect_gt(nrow(lanes), 0)
  expect_true(all(as.character(lanes$facility_type) %in% cl_facility_levels()))
  expect_true(any(lanes$facility_type == "separated_path"))

  s <- cl_summary(lanes)
  expect_gt(sum(s$length_km), 0)
})

test_that("live: Denver official layer reads and standardises", {
  skip_unless_live("services.arcgis.com")

  den <- cl_fetch_official("denver", bbox = denver_box)
  expect_s3_class(den, "sf")
  expect_gt(nrow(den), 0)
  expect_true(all(c("source_id", "name", "official_class", "facility_type",
                    "status", "proposed_class", "length_m") %in% names(den)))
  expect_false(any(is.na(den$official_class)))
  expect_false(any(den$facility_type == "none"))
  expect_equal(attr(den, "cl_source"), "denver")
})

test_that("live: cl_boundary returns Denver's city polygon and clipping shrinks the box", {
  skip_unless_live("nominatim.openstreetmap.org")

  b <- cl_boundary("Denver, Colorado")
  expect_s3_class(b, "sf")
  expect_true(sf::st_geometry_type(b) %in% c("POLYGON", "MULTIPOLYGON"))
  expect_match(b$name, "Denver")
  # the city polygon is well inside its own bounding box
  bb <- cl_bbox("Denver, Colorado")
  expect_lt(as.numeric(sf::st_area(b)),
            as.numeric(sf::st_area(sf::st_as_sfc(sf::st_bbox(b)))))
  expect_true(all(abs(as.numeric(sf::st_bbox(b)) - bb) < 0.01))
})

test_that("live: OSM and official layers compare", {
  skip_unless_live("overpass-api.de")

  lanes <- cl_bike_lanes(denver_box, timeout = 120)
  den <- cl_fetch_official("denver", bbox = denver_box)
  cmp <- cl_compare(lanes, den)
  expect_true(all(cmp$summary$matched_frac >= 0 & cmp$summary$matched_frac <= 1))
  expect_gt(cmp$summary$matched_frac[1], 0.2)
})

test_that("live: Austin official layer reads, sits in Austin, and has no unmapped classes", {
  skip_unless_live("services.arcgis.com")
  # a box over downtown Austin (Lady Bird Lake, Congress Ave)
  austin_box <- c(-97.760, 30.255, -97.730, 30.275)
  atx <- cl_fetch_official("austin", bbox = austin_box)
  expect_gt(nrow(atx), 0)
  expect_false(any(atx$facility_type == "none"))
  bb <- sf::st_bbox(atx)
  expect_true(bb[["xmin"]] > -98 && bb[["xmax"]] < -97 && bb[["ymin"]] > 30 && bb[["ymax"]] < 31)
  expect_true(all(c("comfort", "line_type", "recommended_class") %in% names(atx)))
})

test_that("live: the extract backend reads a small region without Overpass", {
  skip_unless_live("download.geofabrik.de")
  skip_if_not_installed("osmextract")
  # the District of Columbia extract is ~20 MB; a box around the Mall
  dc <- c(-77.05, 38.885, -77.01, 38.905)
  x <- cl_fetch_osm(dc, backend = "extract", clip = FALSE)
  expect_s3_class(x, "sf")
  expect_gt(nrow(x), 20)
  expect_equal(attr(x, "cl_backend"), "extract")
  lanes <- cl_classify(x, drop_none = TRUE)
  expect_true(any(lanes$facility_type %in% c("protected_lane", "painted_lane", "separated_path")))
})

test_that("live: Seattle and Boulder layers read, sit in the right city, and have no unmapped classes", {
  skip_unless_live("services.arcgis.com")
  sea <- cl_fetch_official("seattle", bbox = c(-122.35, 47.60, -122.32, 47.62))
  expect_gt(nrow(sea), 0)
  expect_false(any(sea$facility_type == "none"))
  bb <- sf::st_bbox(sea)
  expect_true(bb[["xmin"]] > -122.5 && bb[["xmax"]] < -122.2 && bb[["ymin"]] > 47.5 && bb[["ymax"]] < 47.75)

  # Boulder is a MapServer capped at 1000 rows per page
  bou <- cl_fetch_official("boulder", bbox = c(-105.29, 40.01, -105.26, 40.03))
  expect_gt(nrow(bou), 0)
  bb <- sf::st_bbox(bou)
  expect_true(bb[["xmin"]] > -105.4 && bb[["xmax"]] < -105.1 && bb[["ymin"]] > 39.9 && bb[["ymax"]] < 40.1)
  expect_true(all(c("street_class", "buffered") %in% names(bou)))
})

test_that("live: Denver bicycle crashes read for one year in the downtown box", {
  skip_unless_live("services1.arcgis.com")
  x <- cl_fetch_crashes("denver", years = 2023, bbox = c(-105.02, 39.73, -104.97, 39.77))
  expect_gt(nrow(x), 5)
  expect_true(all(x$year == 2023))
  expect_true(all(x$bicycle))
  expect_true(all(as.character(x$severity) %in% c("fatal", "serious", "minor", "none", "unknown")))
  expect_true(any(x$location_type == "intersection"))
})

test_that("live: FARS 2022 has bicyclist fatalities inside Denver", {
  skip_unless_live("static.nhtsa.gov")
  x <- cl_fetch_fars(2022, bbox = c(-105.11, 39.61, -104.60, 39.91))
  expect_gt(nrow(x), 0)
  expect_lt(nrow(x), 40)
  expect_true(all(x$bicycle))
  expect_true(all(as.character(x$severity) == "fatal"))
})
