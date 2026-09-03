test_that("cl_summary totals length by facility type", {
  out <- cl_classify(ways(
    c(highway = "residential", cycleway = "lane"),
    c(highway = "residential", cycleway = "lane"),
    c(highway = "primary", cycleway = "track")
  ))
  s <- cl_summary(out)
  expect_equal(as.character(s$facility_type), c("protected_lane", "painted_lane"))
  expect_equal(s$n_segments, c(1L, 2L))
  expect_equal(s$length_km, c(sum(out$length_m[3]), sum(out$length_m[1:2])) / 1000)
  expect_equal(s$length_mi, s$length_km * 0.621371)
  expect_equal(sum(s$share), 1)
})

test_that("cl_summary groups on several columns", {
  out <- cl_classify(ways(
    c(highway = "residential", cycleway = "lane"),
    c(highway = "primary", cycleway = "lane")
  ))
  s <- cl_summary(out, by = c("facility_type", "highway"))
  expect_equal(nrow(s), 2L)
  expect_true(all(c("facility_type", "highway") %in% names(s)))
})

test_that("cl_summary errors on a missing column or non-sf", {
  out <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  expect_error(cl_summary(out, by = "nope"), "not found")
  expect_error(cl_summary(data.frame()), "must be an sf")
})
