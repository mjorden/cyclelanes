square <- function(xmin, ymin, xmax, ymax) {
  sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(xmin, ymin), c(xmax, ymin), c(xmax, ymax), c(xmin, ymax), c(xmin, ymin)
  ))), crs = 4326))
}

test_that("cl_boundary passes an sf polygon through, unioned and in WGS84", {
  sq <- square(-105.01, 39.70, -104.99, 39.72)
  b <- cl_boundary(sq)
  expect_s3_class(b, "sf")
  expect_equal(nrow(b), 1L)
  expect_true(sf::st_geometry_type(b) %in% c("POLYGON", "MULTIPOLYGON"))
  expect_equal(sf::st_crs(b)$epsg, 4326L)

  utm <- sf::st_transform(sq, 32613)
  b2 <- cl_boundary(utm)
  expect_equal(sf::st_crs(b2)$epsg, 4326L)
  expect_equal(as.numeric(sf::st_area(b2)), as.numeric(sf::st_area(b)), tolerance = 1e-6)

  two <- rbind(square(-105.01, 39.70, -105.00, 39.72), square(-105.00, 39.70, -104.99, 39.72))
  expect_equal(nrow(cl_boundary(two)), 1L)
})

test_that("cl_boundary rejects non-polygons and bad inputs", {
  pt <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(-105, 39.7)), crs = 4326))
  expect_error(cl_boundary(pt), "polygon")
  nocrs <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(-105, 39.7))))
  expect_error(cl_boundary(nocrs), "CRS")
  expect_error(cl_boundary(42), "place name")
})

test_that("the polygon_geojson response is parsed and the best polygon chosen", {
  json <- '[
    {"class":"highway","type":"residential","display_name":"Denver St",
     "geojson":{"type":"LineString","coordinates":[[-105,39.7],[-104.99,39.7]]}},
    {"class":"place","type":"city","display_name":"Denver (place)","osm_type":"node","osm_id":"1",
     "geojson":{"type":"Point","coordinates":[-104.99,39.74]}},
    {"class":"boundary","type":"administrative","display_name":"Denver, Colorado","osm_type":"relation","osm_id":"1411339",
     "geojson":{"type":"Polygon","coordinates":[[[-105.1,39.6],[-104.6,39.6],[-104.6,39.9],[-105.1,39.9],[-105.1,39.6]]]}},
    {"class":"place","type":"suburb","display_name":"Denver Heights","osm_type":"relation","osm_id":"2",
     "geojson":{"type":"Polygon","coordinates":[[[-105,39.7],[-104.9,39.7],[-104.9,39.8],[-105,39.8],[-105,39.7]]]}}
  ]'
  b <- cyclelanes:::.parse_nominatim_geojson(json)
  expect_s3_class(b, "sf")
  expect_equal(b$name, "Denver, Colorado")
  expect_equal(b$osm_id, "1411339")
  expect_equal(as.numeric(sf::st_bbox(b)), c(-105.1, 39.6, -104.6, 39.9))

  expect_null(cyclelanes:::.parse_nominatim_geojson("[]"))
  expect_null(cyclelanes:::.parse_nominatim_geojson('[{"class":"place","geojson":{"type":"Point","coordinates":[0,0]}}]'))
  expect_null(cyclelanes:::.parse_nominatim_geojson("nope"))
})

test_that("the polygon URL asks Nominatim for GeoJSON polygons", {
  expect_match(cyclelanes:::.nominatim_url("x", polygon = TRUE), "polygon_geojson=1", fixed = TRUE)
  expect_false(grepl("polygon_geojson", cyclelanes:::.nominatim_url("x")))
})

test_that(".clip_lines keeps inside, cuts crossing, drops outside, keeps attributes", {
  b <- square(-105.0005, 39.705, -104.9985, 39.725)   # ~170 m wide box
  w <- ways(
    c(highway = "residential", cycleway = "lane", name = "inside"),   # y = 39.71, x -105 .. -104.999  (inside)
    c(highway = "residential", cycleway = "lane", name = "crossing"), # y = 39.72, same x, inside
    c(highway = "residential", cycleway = "lane", name = "outside")   # y = 39.73, above the box
  )
  # shift the second way so it starts outside the western edge and crosses in
  g <- sf::st_geometry(w)
  g[[2]] <- sf::st_linestring(rbind(c(-105.002, 39.72), c(-104.999, 39.72)))
  sf::st_geometry(w) <- g
  w <- cl_classify(w)

  out <- cyclelanes:::.clip_lines(w, b)
  expect_equal(sort(out$name), c("crossing", "inside"))
  expect_equal(sf::st_crs(out), sf::st_crs(w))
  inside_len <- w$length_m[w$name == "inside"]
  expect_equal(out$length_m[out$name == "inside"], inside_len, tolerance = 1e-6)
  # the crossing way ran 0.003 deg; only the 0.0015 deg inside the box survives
  cross_len <- out$length_m[out$name == "crossing"]
  expect_gt(cross_len, 0.45 * w$length_m[w$name == "crossing"])
  expect_lt(cross_len, 0.55 * w$length_m[w$name == "crossing"])
  expect_true(all(c("facility_type", "osm_id") %in% names(out)))
})

test_that(".clip_lines handles empty input and non-polygon boundaries", {
  w <- cl_classify(ways(c(highway = "residential", cycleway = "lane")))
  expect_equal(nrow(cyclelanes:::.clip_lines(w[0, ], square(-1, -1, 1, 1))), 0L)
  line <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(0, 0), c(1, 1))), crs = 4326))
  expect_error(cyclelanes:::.clip_lines(w, line), "polygon")
})

test_that(".resolve_clip follows the documented rules", {
  sq <- square(-105.01, 39.70, -104.99, 39.72)
  expect_null(cyclelanes:::.resolve_clip(c(-105, 39, -104, 40), TRUE))
  expect_null(cyclelanes:::.resolve_clip("Denver", FALSE))
  expect_s3_class(cyclelanes:::.resolve_clip(c(-105, 39, -104, 40), sq), "sf")
  expect_error(cyclelanes:::.resolve_clip("Denver", NA), "clip")
  expect_error(cyclelanes:::.resolve_clip("Denver", "yes"), "clip")
})

test_that("cl_fetch_official clips to a polygon bbox", {
  withr::defer(rm(list = ls(cyclelanes:::.cl_registry), envir = cyclelanes:::.cl_registry))
  raw <- sf::st_sf(
    CLS = c("Lane", "Lane"),
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(-105.000, 39.71), c(-104.999, 39.71))),   # inside
      sf::st_linestring(rbind(c(-105.002, 39.72), c(-104.999, 39.72))),   # crosses west edge
      crs = 4326
    )
  )
  path <- withr::local_tempfile(fileext = ".geojson")
  sf::st_write(raw, path, quiet = TRUE)
  cl_register_source("cliptown", url = path, type = "file", class_field = "CLS",
                     crosswalk = c(Lane = "painted_lane"))
  b <- square(-105.0005, 39.705, -104.9985, 39.725)

  whole <- cl_fetch_official("cliptown")
  clipped <- cl_fetch_official("cliptown", bbox = b)
  expect_equal(nrow(clipped), 2L)
  expect_lt(sum(clipped$length_m), sum(whole$length_m))
  expect_s3_class(attr(clipped, "cl_boundary"), "sf")
  expect_null(attr(whole, "cl_boundary"))
})
