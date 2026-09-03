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

test_that("live: OSM and official layers compare", {
  skip_unless_live("overpass-api.de")

  lanes <- cl_bike_lanes(denver_box, timeout = 120)
  den <- cl_fetch_official("denver", bbox = denver_box)
  cmp <- cl_compare(lanes, den)
  expect_true(all(cmp$summary$matched_frac >= 0 & cmp$summary$matched_frac <= 1))
  expect_gt(cmp$summary$matched_frac[1], 0.2)
})
