test_that("cycleway=* values map to the expected facility level", {
  expect_equal(ft(c(highway = "residential", cycleway = "track")), "protected_lane")
  expect_equal(ft(c(highway = "residential", cycleway = "lane")), "painted_lane")
  expect_equal(ft(c(highway = "residential", cycleway = "shared_lane")), "shared_lane")
  expect_equal(ft(c(highway = "residential", cycleway = "share_busway")), "bus_bike_lane")
  expect_equal(ft(c(highway = "residential", cycleway = "shoulder")), "shoulder")
  expect_equal(ft(c(highway = "residential", cycleway = "no")), "none")
  expect_equal(ft(c(highway = "residential", cycleway = "separate")), "none")
  expect_equal(ft(c(highway = "residential", cycleway = "sidepath")), "none")
  expect_equal(ft(c(highway = "residential", cycleway = "crossing")), "none")
})

test_that("unrecognised values and absent tags are 'none'", {
  expect_equal(ft(c(highway = "residential", cycleway = "banana")), "none")
  expect_equal(ft(c(highway = "residential")), "none")
})

test_that("tag values are normalised for case and whitespace", {
  expect_equal(ft(c(highway = "residential", cycleway = " Lane ")), "painted_lane")
  expect_equal(ft(c(highway = "residential", cycleway = "TRACK")), "protected_lane")
})

test_that("highway=cycleway is a separated path with NA sides", {
  out <- cl_classify(ways(c(highway = "cycleway")))
  expect_equal(as.character(out$facility_type), "separated_path")
  expect_true(is.na(out$facility_left))
  expect_true(is.na(out$facility_right))
  expect_true(is.na(out$n_sides))
})

test_that("designated paths are shared-use paths; permissive footways are not facilities", {
  expect_equal(ft(c(highway = "path", bicycle = "designated")), "shared_use_path")
  expect_equal(ft(c(highway = "footway", bicycle = "designated")), "shared_use_path")
  expect_equal(ft(c(highway = "pedestrian", bicycle = "designated")), "shared_use_path")
  expect_equal(ft(c(highway = "footway", bicycle = "yes")), "none")
  expect_equal(ft(c(highway = "residential", bicycle = "designated")), "none")
})

test_that("a cycleway shared with pedestrians is a shared-use path, a dedicated one is not", {
  out <- cl_classify(ways(
    c(highway = "cycleway"),
    c(highway = "cycleway", foot = "designated"),
    c(highway = "cycleway", segregated = "no"),
    c(highway = "cycleway", segregated = "yes", foot = "yes"),
    c(highway = "cycleway", foot = "no")
  ))
  expect_equal(as.character(out$facility_type),
               c("separated_path", "shared_use_path", "shared_use_path",
                 "separated_path", "separated_path"))
  expect_true(all(is.na(out$facility_left)))
  expect_true(all(is.na(out$n_sides)))
})

test_that("sidewalks are never facilities, whatever their bicycle tag", {
  out <- cl_classify(ways(
    c(highway = "footway", footway = "sidewalk", bicycle = "designated"),
    c(highway = "footway", footway = "crossing", bicycle = "designated"),
    c(highway = "footway", footway = "sidewalk", bicycle = "yes"),
    c(highway = "footway", bicycle = "designated")
  ))
  expect_equal(as.character(out$facility_type),
               c("none", "none", "none", "shared_use_path"))
})

test_that("strict drops unpaved or unsurfaced shared paths but never cycleways", {
  w <- ways(
    c(highway = "path", bicycle = "designated"),                        # no surface
    c(highway = "path", bicycle = "designated", surface = "dirt"),
    c(highway = "path", bicycle = "designated", surface = "asphalt"),
    c(highway = "footway", bicycle = "designated", surface = "paving_stones"),
    c(highway = "cycleway", foot = "designated"),                       # shared cycleway, no surface
    c(highway = "cycleway", surface = "gravel")
  )
  lax <- cl_classify(w)
  expect_equal(as.character(lax$facility_type),
               c("shared_use_path", "shared_use_path", "shared_use_path",
                 "shared_use_path", "shared_use_path", "separated_path"))
  strict <- cl_classify(w, strict = TRUE)
  expect_equal(as.character(strict$facility_type),
               c("none", "none", "shared_use_path", "shared_use_path",
                 "shared_use_path", "separated_path"))
})

test_that("shared_with_pedestrians follows the path kind and permissive foot access", {
  out <- cl_classify(ways(
    c(highway = "cycleway"),
    c(highway = "cycleway", foot = "yes"),
    c(highway = "cycleway", foot = "designated"),
    c(highway = "cycleway", segregated = "no"),
    c(highway = "path", bicycle = "designated"),
    c(highway = "residential", cycleway = "lane", foot = "yes")
  ))
  expect_equal(out$shared_with_pedestrians, c(FALSE, TRUE, TRUE, TRUE, TRUE, FALSE))
})

test_that("left/right/both tags resolve per side and overall takes the better side", {
  out <- cl_classify(ways(
    c(highway = "primary", `cycleway:left` = "lane", `cycleway:right` = "track"),
    c(highway = "primary", cycleway = "lane", `cycleway:right` = "no"),
    c(highway = "primary", cycleway = "lane", `cycleway:both` = "track"),
    c(highway = "primary", `cycleway:right` = "shared_lane")
  ))
  expect_equal(as.character(out$facility_left),
               c("painted_lane", "painted_lane", "protected_lane", "none"))
  expect_equal(as.character(out$facility_right),
               c("protected_lane", "none", "protected_lane", "shared_lane"))
  expect_equal(as.character(out$facility_type),
               c("protected_lane", "painted_lane", "protected_lane", "shared_lane"))
  expect_equal(out$n_sides, c(2L, 1L, 2L, 1L))
})

test_that("buffer tags upgrade painted lanes only", {
  out <- cl_classify(ways(
    c(highway = "primary", cycleway = "lane", `cycleway:buffer` = "yes"),
    c(highway = "primary", cycleway = "lane", `cycleway:left:buffer` = "1.5"),
    c(highway = "primary", cycleway = "lane", `cycleway:buffer` = "no"),
    c(highway = "primary", cycleway = "track", `cycleway:buffer` = "yes"),
    c(highway = "primary", cycleway = "lane", `cycleway:both:buffer` = "0.6")
  ))
  expect_equal(as.character(out$facility_left),
               c("buffered_lane", "buffered_lane", "painted_lane", "protected_lane", "buffered_lane"))
  expect_equal(as.character(out$facility_right),
               c("buffered_lane", "painted_lane", "painted_lane", "protected_lane", "buffered_lane"))
  expect_equal(as.character(out$facility_type),
               c("buffered_lane", "buffered_lane", "painted_lane", "protected_lane", "buffered_lane"))
})

test_that("contraflow tagging is classified and flagged", {
  out <- cl_classify(ways(
    c(highway = "residential", cycleway = "opposite_lane"),
    c(highway = "residential", cycleway = "opposite_track"),
    c(highway = "residential", cycleway = "opposite"),
    c(highway = "residential", `cycleway:left` = "opposite_lane"),
    c(highway = "residential", cycleway = "lane")
  ))
  expect_equal(as.character(out$facility_type),
               c("painted_lane", "protected_lane", "shared_lane", "painted_lane", "painted_lane"))
  expect_equal(out$contraflow, c(TRUE, TRUE, TRUE, TRUE, FALSE))
})

test_that("bicycle roads fill sides that have nothing better", {
  out <- cl_classify(ways(
    c(highway = "residential", bicycle_road = "yes"),
    c(highway = "residential", bicycle_road = "yes", cycleway = "no"),
    c(highway = "residential", cyclestreet = "yes", cycleway = "lane"),
    c(highway = "residential", bicycle_road = "yes", `cycleway:right` = "track")
  ))
  expect_equal(as.character(out$facility_type),
               c("neighborhood_bikeway", "neighborhood_bikeway", "painted_lane", "protected_lane"))
  expect_equal(as.character(out$facility_left),
               c("neighborhood_bikeway", "neighborhood_bikeway", "painted_lane", "neighborhood_bikeway"))
  expect_equal(out$n_sides, c(2L, 2L, 2L, 2L))
})

test_that("drop_none removes non-facilities and keep_tags keeps raw columns", {
  w <- ways(
    c(highway = "residential", cycleway = "lane", lit = "yes"),
    c(highway = "residential", cycleway = "no", lit = "no")
  )
  out <- cl_classify(w, drop_none = TRUE)
  expect_equal(nrow(out), 1L)
  expect_false("lit" %in% names(out))

  out2 <- cl_classify(w, keep_tags = TRUE)
  expect_true("lit" %in% names(out2))
  expect_equal(nrow(out2), 2L)
})

test_that("output has the documented columns and factor levels", {
  out <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  expect_s3_class(out, "sf")
  expect_true(all(c("osm_id", "name", "highway", "facility_type", "facility_left",
                    "facility_right", "n_sides", "contraflow", "shared_with_pedestrians",
                    "oneway", "surface", "length_m") %in% names(out)))
  expect_equal(levels(out$facility_type), cl_facility_levels())
  expect_equal(levels(out$facility_left), cl_facility_levels())
})

test_that("length_m is geodesic metres", {
  out <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  # 0.001 deg of longitude at 39.71 N is about 85.6 m
  expect_gt(out$length_m, 80)
  expect_lt(out$length_m, 90)
})

test_that("cl_classify tolerates an input with no tag columns at all", {
  w <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(-105, 39.7), c(-104.999, 39.7))), crs = 4326))
  out <- cl_classify(w)
  expect_equal(as.character(out$facility_type), "none")
  expect_equal(nrow(cl_classify(w, drop_none = TRUE)), 0L)
})

test_that("cl_classify rejects non-sf input", {
  expect_error(cl_classify(data.frame(cycleway = "lane")), "must be an sf")
})

test_that("cl_facility_levels is ordered most to least protected", {
  lv <- cl_facility_levels()
  expect_equal(lv[1], "separated_path")
  expect_equal(lv[length(lv)], "none")
  expect_lt(match("separated_path", lv), match("shared_use_path", lv))
  expect_lt(match("shared_use_path", lv), match("protected_lane", lv))
  expect_lt(match("protected_lane", lv), match("painted_lane", lv))
  expect_lt(match("painted_lane", lv), match("shared_lane", lv))
  expect_setequal(names(cl_palette()), lv)
})

test_that("a cycleway drawn beside the road as its own way is a protected lane", {
  out <- cl_classify(ways(
    c(highway = "cycleway", is_sidepath = "yes"),
    c(highway = "cycleway", cycleway = "track"),
    c(highway = "cycleway", `cycleway:right` = "track"),
    c(highway = "cycleway", is_sidepath = "no"),
    c(highway = "cycleway", is_sidepath = "yes", foot = "designated"),
    c(highway = "cycleway")
  ))
  expect_equal(as.character(out$facility_type),
               c("protected_lane", "protected_lane", "protected_lane",
                 "separated_path", "protected_lane", "separated_path"))
  expect_equal(out$mapped_separately, c(TRUE, TRUE, TRUE, FALSE, TRUE, FALSE))
  expect_true(all(is.na(out$facility_left)))
  expect_true(all(is.na(out$n_sides)))
  # a track tagged on a road is not "mapped separately"
  road <- cl_classify(ways(c(highway = "primary", cycleway = "track")))
  expect_false(road$mapped_separately)
  expect_equal(as.character(road$facility_type), "protected_lane")
})

test_that("a cycleway named like a street is a sidepath; trails are not", {
  out <- cl_classify(ways(
    c(highway = "cycleway", name = "14th Street"),
    c(highway = "cycleway", name = "Lawrence St"),
    c(highway = "cycleway", name = "E 17th Avenue NE"),
    c(highway = "cycleway", name = "Cherry Creek Trail"),
    c(highway = "cycleway", name = "Platte River Greenway"),
    c(highway = "cycleway", name = "Broadway Bike Path"),
    c(highway = "cycleway", name = "Speer Boulevard Bike Lane"),
    c(highway = "cycleway")
  ))
  expect_equal(as.character(out$facility_type),
               c("protected_lane", "protected_lane", "protected_lane",
                 "separated_path", "separated_path", "separated_path",
                 "protected_lane", "separated_path"))
  expect_equal(out$mapped_separately, c(TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, FALSE))

  off <- cl_classify(ways(c(highway = "cycleway", name = "14th Street")), sidepath_by_name = FALSE)
  expect_equal(as.character(off$facility_type), "separated_path")
  # the name rule only applies to cycleways
  road <- cl_classify(ways(c(highway = "residential", name = "14th Street")))
  expect_equal(as.character(road$facility_type), "none")
})

test_that(".street_like_name handles NA, punctuation and directions", {
  f <- cyclelanes:::.street_like_name
  expect_equal(f(c(NA, "", "Main St.", "Elm Street SW", "Bear Creek Trail", "The Path")),
               c(FALSE, FALSE, TRUE, TRUE, FALSE, FALSE))
})
