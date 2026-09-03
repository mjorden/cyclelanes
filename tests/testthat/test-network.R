# cl_as_sfnetwork() and cl_components() on synthetic lanes.

skip_if_not_installed("sfnetworks")

# three east-west protected lanes on one street segment chain, and a
# separate one far away; a painted lane that links the two clusters
hline <- function(x0, x1, y) sf::st_linestring(rbind(c(x0, y), c(x1, y)))
vline <- function(x, y0, y1) sf::st_linestring(rbind(c(x, y0), c(x, y1)))

lanes_sf <- function() {
  sf::st_sf(
    osm_id = as.character(1:5),
    name = c("A", "B", "C", "D", "link"),
    highway = c("primary", "primary", "primary", "primary", "residential"),
    facility_type = factor(c("protected_lane", "protected_lane", "protected_lane", "protected_lane", "painted_lane"),
                           levels = cl_facility_levels()),
    road_maxspeed_kph = c(NA, NA, NA, NA, 40),
    road_lanes = c(NA, NA, NA, NA, 2L),
    geometry = sf::st_sfc(
      hline(-105.000, -104.999, 39.700),   # A
      hline(-104.999, -104.998, 39.700),   # B, shares an endpoint with A
      hline(-104.998, -104.997, 39.7000004), # C, 4 cm off B's end: snapped
      hline(-104.990, -104.989, 39.710),   # D, far away
      sf::st_linestring(rbind(c(-104.997, 39.700), c(-104.990, 39.710))),  # link C's end to D's start
      crs = 4326)
  )
}

test_that("the network snaps near-miss endpoints and keeps edge attributes", {
  x <- lanes_sf()
  x$length_m <- as.numeric(sf::st_length(x))
  net <- cl_as_sfnetwork(x, tolerance = 5)
  expect_s3_class(net, "sfnetwork")
  edges <- sf::st_as_sf(net, "edges")
  expect_equal(nrow(edges), 5L)
  expect_true(all(c("facility_type", "length_m") %in% names(edges)))
  # A-B-C form a chain: B's from node is A's to node, and C joins B
  expect_equal(edges$from[2], edges$to[1])
  expect_equal(edges$from[3], edges$to[2])
})

test_that("components split by stress level", {
  x <- lanes_sf()
  all_c <- cl_components(x)
  expect_equal(max(all_c$component), 1L)          # the link joins everything
  comps <- attr(all_c, "components")
  expect_equal(nrow(comps), 1L)
  expect_equal(comps$share, 1)

  low <- cl_components(x, max_lts = 1)             # drop the painted link (LTS 2)
  expect_equal(nrow(low), 4L)
  expect_equal(max(low$component), 2L)
  comps <- attr(low, "components")
  expect_equal(comps$component, 1:2)
  expect_true(comps$length_km[1] > comps$length_km[2])   # A+B+C is the largest
  expect_equal(comps$n_segments, c(3L, 1L))
  expect_equal(low$component[low$name == "D"], 2L)
  expect_true(all(low$component[low$name %in% c("A", "B", "C")] == 1L))
  expect_equal(sf::st_crs(low)$epsg, 4326L)
})

test_that("cl_components validates and handles empties", {
  x <- lanes_sf()
  expect_error(cl_components(x, max_lts = 7), "1-4")
  expect_error(cl_components(data.frame()), "must be an sf")
  none <- cl_components(x[0, ])
  expect_equal(nrow(none), 0L)
  expect_equal(nrow(attr(none, "components")), 0L)
})

test_that("the fixture forms a small number of low-stress islands", {
  lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
  low <- cl_components(lanes, max_lts = 2)
  comps <- attr(low, "components")
  expect_gt(nrow(comps), 1)
  expect_equal(sum(comps$share), 1, tolerance = 1e-8)
  expect_true(all(diff(comps$length_km) <= 1e-9))
  skip_if_not_installed("ggplot2")
  expect_s3_class(cl_plot(low, colour = "component"), "ggplot")
})
