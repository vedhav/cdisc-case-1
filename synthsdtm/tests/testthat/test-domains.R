test_that("the inventory covers all 63 SDTMIG 3.4 domains", {
  d <- sdtm_domains()
  expect_equal(nrow(d), 63)
  expect_setequal(unique(d$class),
    c("Special-Purpose", "Interventions", "Events", "Findings", "Findings About",
      "Trial Design", "Study Reference", "Relationship"))
  expect_false(any(duplicated(d$domain)))
})

test_that("supported domains are exactly those with a template + builder", {
  expect_setequal(supported_domains(),
    c("DM", "IE", "MH", "VS", "EG", "LB", "EX", "CM", "AE", "DS", "PC", "PE"))
  d <- sdtm_domains()
  expect_setequal(d$domain[d$supported], supported_domains())
})

test_that("PC (numeric) and PE (categorical) generate via the findings builder", {
  # Extend the complete toy config (has EX/DS for RF* reconciliation) with PC + PE.
  cfg <- jsonlite::read_json(system.file("configs", "toy_parallel.json", package = "synthsdtm"),
                             simplifyVector = FALSE)
  # Drop AE to keep this test focused on PC/PE (AE's count bound is stochastic at small N).
  cfg$domains$AE <- NULL
  cfg$sourceActivities$AE <- NULL
  cfg$sourceActivities$PC <- list(list(activityId = "ACT_PK", activityName = "PK sampling",
                                        bcNcit = NULL, protocolPage = 7))
  cfg$sourceActivities$PE <- list(list(activityId = "ACT_PE", activityName = "Physical exam",
                                        bcNcit = NULL, protocolPage = 6))
  cfg$domains$PC <- list(builder = "findings", tests = list(
    list(testcd = "DRUGX", test = "Drug X", category = "ANALYTE", specimen = "PLASMA",
         unit = "ng/mL", low = 5, high = 200, decimals = 1,
         occursAt = list("ENC_D1", "ENC_FU"), sourceActivity = "ACT_PK")))
  cfg$domains$PE <- list(builder = "findings", tests = list(
    list(testcd = "CARDIO", test = "Cardiovascular", category = "PHYSICAL EXAM",
         choices = list("NORMAL", "ABNORMAL"),
         occursAt = list("ENC_SCR"), sourceActivity = "ACT_PE")))

  built <- build_spec(cfg)
  res <- simulate_sdtm(cfg, built$spec, built$ct_cache, n_subjects = 4, seed = 1)
  expect_equal(nrow(res$domains$PC), 4 * 2)        # 4 subjects x 2 visits
  expect_equal(nrow(res$domains$PE), 4 * 1)        # 4 subjects x 1 visit
  expect_true(all(res$domains$PE$PEORRES %in% c("NORMAL", "ABNORMAL")))
  expect_true(all(res$domains$PC$PCSTRESN != ""))  # numeric result populated
  expect_true(all(res$domains$PC$PCSPEC == "PLASMA"))
  expect_false("PESTRESN" %in% names(res$domains$PE))  # PE carries no numeric-result column

  run <- withr::local_tempdir()
  write_sdtm(res, run)
  rep <- check_sdtm(cfg, built$spec, built$ct_cache, run_dir = run, n_subjects = 4, seed = 1)
  expect_true(rep$allPass)
})

test_that("build_spec fails clearly for an untemplated domain", {
  # Schema-valid config whose only problem is an in-scope domain (TU) with no
  # SDTMIG template — exercises the template check, not config validation.
  cfg <- list(
    studyId = "X", design = "parallel",
    cohorts = list(list(armcd = "A", arm = "Arm A", n = 1, treatments = list("Drug X"))),
    demographics = list(ageRange = list(18, 65), sexes = list("M"), races = list("WHITE"),
                        ethnicities = list("NOT HISPANIC OR LATINO"),
                        heightCm = list(150, 190), weightKg = list(50, 100)),
    visitGrid = list(ENC_V1 = list(label = "DAY 1", dayOffset = 1, visitNum = 1, epoch = "TREATMENT")),
    domains = list(TU = list(builder = "findings",
                             tests = list(list(testcd = "X", test = "X", occursAt = list("ENC_V1"))))))
  expect_error(build_spec(cfg), "No SDTMIG template")
})

test_that("build_spec rejects a config with a typo'd knob", {
  cfg <- jsonlite::read_json(system.file("configs", "NCT04556760.json", package = "synthsdtm"),
                             simplifyVector = FALSE)
  cfg$knobs$aeIncidenceTYPO <- 0.9
  expect_error(build_spec(cfg), "not conform|Unknown knob|additional")
})
