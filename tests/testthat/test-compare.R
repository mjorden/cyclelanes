official_like <- function(sf_obj, class = "Bike Lane") {
  out <- sf::st_sf(
    source_id = as.character(seq_len(nrow(sf_obj))),
    name = NA_character_,
    official_class = class,
    facility_type = factor("painted_lane", levels = cl_facility_levels()),
    geometry = sf::st_geometry(sf_obj)
  )
  out$length_m <- as.numeric(sf::st_length(out))
  out
}

test_that("identical geometry matches fully in both directions", {
  osm <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  off <- official_like(osm)
  cmp <- cl_compare(osm, off, tolerance = 5)
  expect_s3_class(cmp, "cl_comparison")
  expect_equal(cmp$summary$matched_frac, c(1, 1))
  expect_equal(cmp$osm$matched_frac, 1)
  expect_equal(cmp$official$matched_frac, 1)
  expect_equal(cmp$summary$length_km, c(osm$length_m, off$length_m) / 1000, tolerance = 1e-6)
})

test_that("disjoint geometry matches nothing", {
  osm <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  shifted <- osm
  sf::st_geometry(shifted) <- sf::st_geometry(osm) + c(0, 0.01)
  sf::st_crs(shifted) <- 4326
  off <- official_like(shifted)
  cmp <- cl_compare(osm, off, tolerance = 15)
  expect_equal(cmp$summary$matched_frac, c(0, 0))
})

test_that("partial overlap gives a partial fraction", {
  osm <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  # official covers only the western half of the OSM way
  half <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(-105, 39.71), c(-104.9995, 39.71))), crs = 4326))
  off <- official_like(half)
  cmp <- cl_compare(osm, off, tolerance = 1)
  expect_gt(cmp$osm$matched_frac, 0.45)
  expect_lt(cmp$osm$matched_frac, 0.6)
  expect_equal(cmp$official$matched_frac, 1)
})

test_that("by_type breaks the match down per layer and facility", {
  osm <- cl_classify(ways(
    c(highway = "residential", cycleway = "lane"),
    c(highway = "primary", cycleway = "track")
  ))
  off <- official_like(osm[1, ])
  cmp <- cl_compare(osm, off, tolerance = 5)
  bt <- cmp$by_type
  expect_equal(bt$layer, c("osm", "osm", "official"))
  osm_rows <- bt[bt$layer == "osm", ]
  expect_equal(osm_rows$matched_frac[osm_rows$facility_type == "painted_lane"], 1)
  expect_equal(osm_rows$matched_frac[osm_rows$facility_type == "protected_lane"], 0)
  expect_output(print(cmp), "cl_comparison")
})

test_that("cl_compare validates its inputs", {
  osm <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  off <- official_like(osm)
  expect_error(cl_compare(osm[0, ], off), "at least one feature")
  expect_error(cl_compare(osm, off, tolerance = -1), "positive")
  expect_error(cl_compare(data.frame(), off), "must be an sf")
  no_type <- off
  no_type$facility_type <- NULL
  expect_error(cl_compare(osm, no_type), "facility_type")
})
