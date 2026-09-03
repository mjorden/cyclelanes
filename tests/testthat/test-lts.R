lts_of <- function(...) {
  out <- cl_lts(cl_classify(ways(...)))
  out$lts
}

test_that("paths and protected lanes are LTS 1 regardless of the road", {
  expect_equal(lts_of(
    c(highway = "cycleway"),
    c(highway = "path", bicycle = "designated"),
    c(highway = "primary", cycleway = "track", maxspeed = "70", lanes = "6")
  ), c(1L, 1L, 1L))
})

test_that("bike lanes step up with speed and width of the road", {
  expect_equal(lts_of(
    c(highway = "residential", cycleway = "lane", maxspeed = "25 mph", lanes = "2"),
    c(highway = "secondary", cycleway = "lane", maxspeed = "30 mph", lanes = "2"),
    c(highway = "secondary", cycleway = "lane", maxspeed = "25 mph", lanes = "5"),
    c(highway = "primary", cycleway = "lane", maxspeed = "45 mph", lanes = "4"),
    c(highway = "primary", `cycleway:right` = "lane", `cycleway:right:buffer` = "yes", maxspeed = "40", lanes = "2")
  ), c(2L, 3L, 3L, 4L, 2L))
})

test_that("mixed traffic and no facility follow the speed and lane rules", {
  expect_equal(lts_of(
    c(highway = "residential", cycleway = "shared_lane", maxspeed = "20 mph", lanes = "2"),
    c(highway = "residential", cycleway = "shared_lane", maxspeed = "25 mph", lanes = "2"),
    c(highway = "tertiary", cycleway = "shared_lane", maxspeed = "25 mph", lanes = "4"),
    c(highway = "primary", cycleway = "shared_lane", maxspeed = "40 mph", lanes = "4"),
    c(highway = "residential", maxspeed = "20 mph", lanes = "2"),
    c(highway = "primary", maxspeed = "45 mph")
  ), c(1L, 2L, 3L, 4L, 1L, 4L))
})

test_that("neighborhood bikeways and bus lanes have their own rules", {
  expect_equal(lts_of(
    c(highway = "residential", bicycle_road = "yes", maxspeed = "25 mph", lanes = "2"),
    c(highway = "residential", bicycle_road = "yes", maxspeed = "30 mph", lanes = "2"),
    c(highway = "primary", cycleway = "share_busway", maxspeed = "30 mph")
  ), c(1L, 2L, 3L))
})

test_that("missing speed or lanes are assumed from the road class and recorded", {
  out <- cl_lts(cl_classify(ways(
    c(highway = "residential", cycleway = "lane"),
    c(highway = "primary", cycleway = "lane"),
    c(highway = "secondary", cycleway = "lane", maxspeed = "50"),
    c(highway = "cycleway")
  )))
  expect_equal(out$lts, c(2L, 4L, 3L, 1L))
  expect_match(out$lts_basis[1], "speed and lanes assumed")
  expect_match(out$lts_basis[3], "lanes assumed")
  expect_false(grepl("assumed", out$lts_basis[4]))
  expect_match(out$lts_basis[4], "off-street")
})

test_that("every rule in the table is reachable and the table is well formed", {
  rules <- cyclelanes:::.lts_rules()
  expect_true(all(c("group", "max_speed_kph", "max_lanes", "lts", "rule") %in% names(rules)))
  expect_true(all(rules$lts %in% 1:4))
  expect_setequal(unique(rules$group), c("path", "bikeway", "lane", "bus", "mixed", "none"))
  # each group ends with a catch-all row
  last <- rules[!duplicated(rules$group, fromLast = TRUE), ]
  expect_true(all(is.na(last$max_speed_kph) & is.na(last$max_lanes)))
})

test_that("cl_lts works on the fixture and cl_plot colours by lts", {
  lanes <- cl_lts(cl_classify(denver_lodo$osm, drop_none = TRUE))
  expect_true(all(lanes$lts %in% 1:4))
  expect_false(any(is.na(lanes$lts)))
  s <- cl_summary(lanes, by = "lts")
  expect_equal(sum(s$share), 1)
  skip_if_not_installed("ggplot2")
  p <- cl_plot(lanes, colour = "lts")
  expect_s3_class(p, "ggplot")
  expect_error(cl_plot(cl_classify(denver_lodo$osm), colour = "lts"), "cl_lts")
})

test_that("cl_lts validates its input", {
  expect_error(cl_lts(data.frame()), "must be an sf")
  expect_error(cl_lts(denver_lodo$osm), "facility_type")
})
