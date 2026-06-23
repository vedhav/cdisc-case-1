test_that("study_day has no day zero", {
  expect_equal(study_day("2020-01-01", "2020-01-01"), 1L)  # ref date is day +1
  expect_equal(study_day("2020-01-02", "2020-01-01"), 2L)
  expect_equal(study_day("2019-12-31", "2020-01-01"), -1L) # day before ref is -1, never 0
  expect_equal(study_day("", "2020-01-01"), "")
})

test_that("gen_value respects bounds and integer-ness", {
  set.seed(1)
  ints <- vapply(1:200, function(i) gen_value(1, 5, NULL), numeric(1))
  expect_true(all(ints >= 1 & ints <= 5))
  expect_true(all(ints == round(ints)))
  decs <- vapply(1:200, function(i) gen_value(0, 1, 2), numeric(1))
  expect_true(all(decs >= 0 & decs <= 1))
})

test_that("parse_dose enforces the placebo-zero rule", {
  parse_dose <- synthsdtm:::parse_dose  # internal helper
  expect_equal(parse_dose("Placebo")$dose, 0)
  pd <- parse_dose("AZD9567 72 mg")
  expect_equal(pd$name, "AZD9567")
  expect_equal(pd$dose, 72)
  expect_equal(pd$unit, "mg")
})
