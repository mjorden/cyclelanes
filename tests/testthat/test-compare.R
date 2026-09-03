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

official_typed <- function(sf_obj, types) {
  out <- sf::st_sf(
    source_id = as.character(seq_len(nrow(sf_obj))),
    name = NA_character_,
    official_class = types,
    facility_type = factor(types, levels = cl_facility_levels()),
    geometry = sf::st_geometry(sf_obj)
  )
  out$length_m <- as.numeric(sf::st_length(out))
  out
}

test_that("type agreement is 1 for the same type and 0 for a different one", {
  osm <- cl_classify(ways(
    c(highway = "residential", cycleway = "lane"),
    c(highway = "primary", cycleway = "track")
  ))
  off <- official_typed(osm, c("painted_lane", "painted_lane"))
  cmp <- cl_compare(osm, off, tolerance = 5)

  expect_equal(as.character(cmp$osm$other_type), c("painted_lane", "painted_lane"))
  expect_equal(cmp$osm$type_match, c(TRUE, FALSE))
  expect_equal(as.character(cmp$official$other_type), c("painted_lane", "protected_lane"))
  expect_equal(cmp$official$type_match, c(TRUE, FALSE))

  s <- cmp$summary
  share <- osm$length_m[1] / sum(osm$length_m)
  expect_equal(s$type_agreement, c(share, share), tolerance = 1e-6)
  bt <- cmp$by_type[cmp$by_type$layer == "osm", ]
  expect_equal(bt$type_agreement[bt$facility_type == "painted_lane"], 1)
  expect_equal(bt$type_agreement[bt$facility_type == "protected_lane"], 0)

  cm <- cmp$confusion
  expect_equal(rownames(cm), "painted_lane")
  expect_setequal(colnames(cm), c("protected_lane", "painted_lane"))
  expect_equal(cm["painted_lane", "painted_lane"], osm$length_m[1] / 1000, tolerance = 1e-6)
  expect_equal(cm["painted_lane", "protected_lane"], osm$length_m[2] / 1000, tolerance = 1e-6)
})

test_that("adjacent levels count as adjacent, not as a match", {
  osm <- cl_classify(ways(c(highway = "residential", cycleway = "lane",
                            `cycleway:buffer` = "yes")))
  off <- official_typed(osm, "painted_lane")
  cmp <- cl_compare(osm, off, tolerance = 5)
  expect_false(cmp$osm$type_match)
  expect_true(cmp$osm$type_adjacent)
  expect_equal(cmp$summary$type_agreement, c(0, 0))
  expect_equal(cmp$summary$type_adjacent, c(1, 1))
})

test_that("unmatched segments have NA other_type and land in the unmatched column", {
  osm <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  shifted <- osm
  sf::st_geometry(shifted) <- sf::st_geometry(osm) + c(0, 0.01)
  sf::st_crs(shifted) <- 4326
  off <- official_typed(shifted, "protected_lane")
  cmp <- cl_compare(osm, off, tolerance = 15)
  expect_true(is.na(cmp$osm$other_type))
  expect_true(is.na(cmp$osm$type_match))
  expect_true(is.na(cmp$summary$type_agreement[1]))
  expect_equal(colnames(cmp$confusion), "unmatched")
  expect_equal(cmp$confusion["protected_lane", "unmatched"], off$length_m / 1000, tolerance = 1e-6)
})

test_that("other_type is the type covering most of the segment", {
  # one long OSM lane; official has a short protected piece and a long painted piece along it
  osm <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  sf::st_geometry(osm) <- sf::st_sfc(
    sf::st_linestring(rbind(c(-105, 39.71), c(-104.997, 39.71))), crs = 4326)
  osm$length_m <- as.numeric(sf::st_length(osm))
  short <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(-105, 39.71), c(-104.9995, 39.71))), crs = 4326))
  long <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(-104.9995, 39.71), c(-104.997, 39.71))), crs = 4326))
  off <- rbind(official_typed(short, "protected_lane"), official_typed(long, "painted_lane"))
  cmp <- cl_compare(osm, off, tolerance = 2)
  expect_equal(as.character(cmp$osm$other_type), "painted_lane")
  expect_true(cmp$osm$type_match)
})

test_that("print shows the confusion matrix and cl_plot colours by type_match", {
  osm <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  off <- official_typed(osm, "protected_lane")
  cmp <- cl_compare(osm, off, tolerance = 5)
  expect_output(print(cmp), "OSM type")
  skip_if_not_installed("ggplot2")
  p <- cl_plot(cmp$official, colour = "type_match")
  expect_s3_class(p, "ggplot")
  expect_error(cl_plot(off, colour = "type_match"), "cl_compare")
})
