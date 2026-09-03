# Regression tests on the frozen downtown Denver fixture. Any change to the
# classification rules or the Denver crosswalk must update the snapshots
# deliberately (testthat::snapshot_accept()).

test_that("the fixture has the documented shape", {
  expect_type(denver_lodo, "list")
  expect_named(denver_lodo, c("osm", "official", "bbox", "fetched"))
  expect_s3_class(denver_lodo$osm, "sf")
  expect_s3_class(denver_lodo$official, "sf")
  expect_s3_class(denver_lodo$fetched, "Date")
  expect_equal(sf::st_crs(denver_lodo$osm)$epsg, 4326L)
  expect_equal(sf::st_crs(denver_lodo$official)$epsg, 4326L)
  expect_gt(nrow(denver_lodo$osm), 50)
  expect_gt(nrow(denver_lodo$official), 10)
  expect_true(all(c("osm_id", "highway") %in% names(denver_lodo$osm)))
  expect_true(all(c("facility_type", "official_class", "status", "length_m") %in%
                    names(denver_lodo$official)))
})

test_that("classifying the fixture is stable", {
  lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
  expect_gt(nrow(lanes), 0)
  expect_true(all(as.character(lanes$facility_type) %in% cl_facility_levels()))
  s <- cl_summary(lanes)
  s$length_km <- round(s$length_km, 2)
  s$length_mi <- round(s$length_mi, 2)
  s$share <- round(s$share, 3)
  s$facility_type <- as.character(s$facility_type)
  expect_snapshot_value(s, style = "json2")

  strict <- cl_classify(denver_lodo$osm, drop_none = TRUE, strict = TRUE)
  expect_lte(nrow(strict), nrow(lanes))
})

test_that("the official fixture summary is stable", {
  s <- cl_summary(denver_lodo$official)
  s$length_km <- round(s$length_km, 2)
  s$length_mi <- round(s$length_mi, 2)
  s$share <- round(s$share, 3)
  s$facility_type <- as.character(s$facility_type)
  expect_snapshot_value(s, style = "json2")
  expect_false(any(s$facility_type == "none"))
})

test_that("comparing the two fixture layers runs and is stable", {
  lanes <- cl_classify(denver_lodo$osm, drop_none = TRUE)
  cmp <- cl_compare(lanes, denver_lodo$official)
  expect_s3_class(cmp, "cl_comparison")
  s <- cmp$summary
  for (col in c("length_km", "matched_km")) s[[col]] <- round(s[[col]], 2)
  for (col in c("matched_frac", "type_agreement", "type_adjacent")) s[[col]] <- round(s[[col]], 3)
  expect_snapshot_value(s, style = "json2")
  expect_gt(cmp$summary$matched_frac[2], 0.5)
})
