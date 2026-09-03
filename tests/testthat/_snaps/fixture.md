# classifying the fixture is stable

    {
      "type": "list",
      "attributes": {
        "names": {
          "type": "character",
          "attributes": {},
          "value": ["facility_type", "n_segments", "length_km", "length_mi", "share"]
        },
        "row.names": {
          "type": "integer",
          "attributes": {},
          "value": [1, 2, 3, 4, 5, 6]
        },
        "class": {
          "type": "character",
          "attributes": {},
          "value": ["data.frame"]
        }
      },
      "value": [
        {
          "type": "character",
          "attributes": {},
          "value": ["separated_path", "shared_use_path", "protected_lane", "buffered_lane", "painted_lane", "shared_lane"]
        },
        {
          "type": "integer",
          "attributes": {},
          "value": [90, 53, 162, 18, 66, 24]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [5.46, 2.29, 12.73, 1.69, 4.07, 1.3]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [3.39, 1.42, 7.91, 1.05, 2.53, 0.81]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [0.198, 0.083, 0.462, 0.061, 0.148, 0.047]
        }
      ]
    }

# the official fixture summary is stable

    {
      "type": "list",
      "attributes": {
        "names": {
          "type": "character",
          "attributes": {},
          "value": ["facility_type", "n_segments", "length_km", "length_mi", "share"]
        },
        "row.names": {
          "type": "integer",
          "attributes": {},
          "value": [1, 2, 3, 4, 5]
        },
        "class": {
          "type": "character",
          "attributes": {},
          "value": ["data.frame"]
        }
      },
      "value": [
        {
          "type": "character",
          "attributes": {},
          "value": ["separated_path", "shared_use_path", "protected_lane", "buffered_lane", "painted_lane"]
        },
        {
          "type": "integer",
          "attributes": {},
          "value": [7, 8, 22, 4, 14]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [1.79, 1.11, 11.02, 0.97, 2.97]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [1.11, 0.69, 6.84, 0.6, 1.85]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [0.1, 0.062, 0.617, 0.054, 0.166]
        }
      ]
    }

# comparing the two fixture layers runs and is stable

    {
      "type": "list",
      "attributes": {
        "names": {
          "type": "character",
          "attributes": {},
          "value": ["layer", "n_segments", "length_km", "matched_km", "matched_frac", "type_agreement", "type_adjacent"]
        },
        "row.names": {
          "type": "integer",
          "attributes": {},
          "value": [1, 2]
        },
        "class": {
          "type": "character",
          "attributes": {},
          "value": ["data.frame"]
        }
      },
      "value": [
        {
          "type": "character",
          "attributes": {},
          "value": ["osm", "official"]
        },
        {
          "type": "integer",
          "attributes": {},
          "value": [413, 55]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [27.54, 17.86]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [25.01, 16.55]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [0.908, 0.927]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [0.733, 0.78]
        },
        {
          "type": "double",
          "attributes": {},
          "value": [0.785, 0.836]
        }
      ]
    }

