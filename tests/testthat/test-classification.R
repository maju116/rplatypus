# One label per image, from R. The constructors first, because they are what a user meets,
# and then the one thing that is only testable against a running engine: that the two paths
# into the specification agree.

test_that("classification_data tags its task and sends only what was asked for", {
  data <- classification_data("train/", "valid/", classes = c("benign", "malignant"))

  expect_identical(attr(data, "task", exact = TRUE), "classification")
  expect_s3_class(data, "platypus_classification_data")
  expect_identical(data$classes, c("benign", "malignant"))

  # The defaults this constructor does not send. A default sent from R is indistinguishable
  # from a value the caller chose, which is how an engine-side default - or a weights file -
  # gets silenced.
  expect_null(data$strict_labels)
  expect_null(data$column_sep)
  expect_null(data$shuffle)
  expect_null(data$mode)

  asked <- classification_data("train/", "valid/", classes = c("a", "b"),
                               strict_labels = FALSE, mode = "config_file")
  expect_false(asked$strict_labels)
  expect_identical(asked$mode, "config_file")
})

test_that("subdirs is refused by name, with the layout in the message", {
  # Named rather than dropped from the signature, because every sibling data constructor
  # has it: a call copied from `segmentation_data()` would otherwise get R's own "unused
  # argument", which says nothing about why.
  expect_error(
    classification_data("train/", "valid/", classes = c("a", "b"),
                        subdirs = c("images", "masks")),
    "single image"
  )
  expect_error(
    classification_data("train/", "valid/", classes = c("a", "b"),
                        subdirs = c("images", "masks")),
    "label"
  )
})

test_that("classes are checked the way a class index has to be", {
  # `validation` given throughout: a data block with nothing to validate against is refused
  # before `classes` is looked at, which is the order `detection_data()` checks in too.
  expect_error(classification_data("train/", "valid/", classes = "only"), "at least two")
  expect_error(classification_data("train/", "valid/", classes = c("a", "a")), "distinct")
  expect_error(classification_data("train/", "valid/", classes = c("a", "")), "non-empty")
  expect_error(classification_data("train/", "valid/"), "class order")
})

test_that("a platypus_split is refused, and the message says what to use instead", {
  split <- structure(
    list(train_path = "t.csv", validation_path = "v.csv", test_path = NULL),
    class = "platypus_split"
  )
  expect_error(classification_data(split, classes = c("a", "b")), "stratifies")
})

test_that("classifier tags its task and drops what nobody set", {
  model <- classifier("cnn", input_shape = c(64, 64))

  expect_identical(attr(model, "task", exact = TRUE), "classification")
  expect_identical(model$input_shape, c(64L, 64L))
  expect_identical(model$name, "cnn")
  # No `architecture`, and that is the point rather than an omission: the contracting path
  # is the network, so `encoder` is the whole answer and a second field naming it would be
  # two places for one fact.
  expect_false("architecture" %in% names(model))
  expect_false("blocks" %in% names(model))
  expect_false("n_class" %in% names(model))

  asked <- classifier("cnn", input_shape = c(64, 64), blocks = 3, pooling = "max",
                      head_dropout = 0.2)
  expect_identical(asked$blocks, 3L)
  expect_identical(asked$pooling, "max")
  expect_identical(asked$head_dropout, 0.2)
})

test_that("the four label metrics are their own family and share no name with the masks'", {
  expect_identical(metric_auc(), list(name = "auc"))
  expect_identical(metric_accuracy(), list(name = "accuracy"))
  expect_identical(metric_balanced_accuracy(), list(name = "balanced_accuracy"))
  expect_identical(metric_f1(), list(name = "f1"))

  label <- c(metric_auc()$name, metric_accuracy()$name,
             metric_balanced_accuracy()$name, metric_f1()$name)
  masks <- c(metric_dice()$name, metric_iou()$name, metric_tversky()$name,
             metric_cldice()$name)
  expect_identical(intersect(label, masks), character(0))
})

test_that("a classifier beside segmentation data is two tasks in one specification", {
  expect_error(
    platypus_spec(
      data = segmentation_data("train/", "valid/", colormap = binary_colormap),
      models = list(classifier("cnn", input_shape = c(64, 64)))
    ),
    "one task"
  )
  expect_error(
    platypus_spec(
      data = classification_data("train/", "valid/", classes = c("a", "b")),
      models = list(u_net("u", input_shape = c(64, 64)))
    ),
    "one task"
  )
})

test_that("the task can be stated, and then it is checked rather than trusted", {
  # `rplatypus:::` rather than a bare call: `spec_task()` is internal, and a bare one
  # resolves under `pkgload::load_all()` and not under the `library()` + `test_dir()` the
  # `engine` job runs. §4's "installed is not source", and this gate is what caught it.
  skip_if_no_engine()
  root <- tiny_classification_dataset()

  stated <- platypus_spec(
    data = classification_data(root, root, classes = c("dark", "bright")),
    models = list(classifier("tiny", input_shape = c(32, 32), blocks = 2, filters = 4)),
    task = "classification"
  )
  expect_identical(rplatypus:::spec_task(stated), "classification")

  expect_error(
    platypus_spec(
      data = classification_data(root, root, classes = c("dark", "bright")),
      models = list(classifier("tiny", input_shape = c(32, 32), blocks = 2, filters = 4)),
      task = "semantic_segmentation"
    ),
    "disagrees"
  )
})

test_that("a YAML file and the constructors reach the same specification", {
  # The divergence this pull request exists to avoid, and the one a pin move on its own
  # would have created. `platypus_spec("file.yaml")` goes straight to the engine's loader
  # with no R constructor involved - so with the pin at `0.8.0a49` and no constructors, a
  # file saying `task: classification` would have been accepted while
  # `classification_data()` did not exist to express it. `rplatypus#152` recorded that shape
  # for `regions`; this is the same check one task across, and the round trip is the form
  # `save_spec()`'s own example uses.
  skip_if_no_engine()
  root <- tiny_classification_dataset()

  from_constructors <- platypus_spec(
    data = classification_data(root, root, classes = c("dark", "bright")),
    models = list(classifier("tiny", input_shape = c(32, 32), blocks = 2, filters = 4))
  )
  path <- withr::local_tempfile(fileext = ".yaml")
  save_spec(from_constructors, path)
  from_file <- platypus_spec(path)

  expect_identical(as.list(from_file), as.list(from_constructors))
  expect_identical(rplatypus:::spec_task(from_file), "classification")

  # **This assertion was the defect, asserted.** It read `expect_error(..., "disagrees")`
  # with a comment saying a bare `data` list "is read as semantic segmentation whatever task
  # is stated", which is what `#239` was filed about the same evening: the inference had no
  # evidence, answered semantic anyway, and refused the stated task for disagreeing with an
  # answer nobody had given. A plain list names no task now, so the task argument is taken,
  # and the third route reaches the same specification as the other two.
  from_bare <- platypus_spec(
    data = list(train_path = root, validation_path = root,
                classes = c("dark", "bright")),
    models = list(list(name = "tiny", input_shape = c(32L, 32L))),
    task = "classification"
  )
  expect_identical(rplatypus:::spec_task(from_bare), "classification")
})

test_that("class_balance counts in class order and prints the engine's own sentence", {
  skip_if_no_engine()
  root <- tiny_classification_dataset(per_class = 3)
  spec <- tiny_classification_spec(root)

  balance <- class_balance(spec, split = "train")
  expect_s3_class(balance, "platypus_class_balance")
  # Class order rather than the order the directories were walked in, which is what makes
  # the `share` column readable beside `classes`.
  expect_identical(balance$class, c("dark", "bright"))
  expect_identical(balance$n, c(3L, 3L))
  expect_equal(sum(balance$share), 1, tolerance = 1e-12)

  # The remark is the engine's string, not a sentence rebuilt here - the threshold it fires
  # below is the engine's number and a copy of it in R would be a second place for one fact.
  remark <- attr(balance, "remark", exact = TRUE)
  expect_true(grepl("6 images in 2 classes", remark, fixed = TRUE))
  expect_output(print(balance), "6 images in 2 classes")
})

test_that("a classifier trains, answers per image, and the answers are joinable", {
  skip_if_no_engine()
  root <- tiny_classification_dataset()
  fit <- platypus_fit(tiny_classification_spec(root), num_workers = 0)

  answers <- predict(fit, split = "validation", type = "class")
  expect_s3_class(answers, "data.frame")
  expect_identical(nrow(answers), 8L)
  expect_identical(names(answers), c("key", "label", "predicted", "probability"))
  # The keys are what joins this to anything else the caller holds, and they are the
  # engine's own rather than this side's idea of the split's order.
  expect_false(anyDuplicated(answers$key) > 0)
  expect_true(all(answers$predicted %in% c("dark", "bright")))
  expect_true(all(answers$probability >= 0 & answers$probability <= 1))

  probabilities <- predict(fit, split = "validation", type = "probability")
  expect_true(is.matrix(probabilities))
  expect_identical(dim(probabilities), c(8L, 2L))
  # The class order is the specification's, and the rows carry the same keys as the table -
  # which is the only thing that makes the two readings of one prediction comparable.
  expect_identical(colnames(probabilities), c("dark", "bright"))
  expect_identical(rownames(probabilities), answers$key)
  expect_equal(unname(rowSums(probabilities)), rep(1, 8), tolerance = 1e-5)
  # And the table's own column is the chosen class's probability rather than the first's,
  # which a two-class fixture is exactly able to tell apart.
  chosen <- probabilities[cbind(seq_len(8), match(answers$predicted, c("dark", "bright")))]
  expect_equal(answers$probability, chosen, tolerance = 1e-6)
})

test_that("evaluate reports the metrics asked for and nothing about a grid", {
  skip_if_no_engine()
  root <- tiny_classification_dataset()
  fit <- platypus_fit(
    tiny_classification_spec(root, metrics = list(metric_auc(), metric_accuracy())),
    num_workers = 0
  )

  table <- evaluate(fit)
  expect_identical(nrow(table), 1L)
  expect_true(all(c("auc", "accuracy") %in% names(table)))
  # Bare names rather than `val_` ones, with a `split` column saying which pass they are
  # from: a row reading `split: validation` beside a column called `val_auc` is a row that
  # has to be explained.
  expect_true("split" %in% names(table))
  expect_false(any(grepl("^val_", names(table))))
  expect_identical(table$architecture, "plain_cnn")

  # `at` chooses the grid a mask is scored on, and a label is not on a grid.
  expect_error(evaluate(fit, at = "source"), "one label per image")
  # A case here is one image, whose score is 0 or 1 - so the spread carries nothing.
  expect_error(evaluate_cases(fit), "0 or 1")
})

test_that("the arguments that describe a grid are refused on a label, by name", {
  # A fake fit rather than a trained one: every one of these refusals fires before anything
  # is asked of the engine, which is the whole point of their being R's.
  fake <- structure(list(task = "classification", models = "cnn"), class = "platypus_fit")

  expect_error(predict(fake, space = "source"), "no grid for a label")
  expect_error(predict(fake, type = "channels"), "one number per class")
  expect_error(predict(fake, cases = "a"), "row per image")
  expect_error(predict(fake, each = function(case, mask) mask), "row per image")
  expect_error(predict(fake, decode = decode_watershed()), "instance model")
  expect_error(evaluate_images(fake), "detection measure")
  expect_error(evaluate_classes(fake), "detection measure")
})

test_that("a detector is told that decode means nothing to it, rather than ignoring it", {
  # The guard used to sit below the task branches, so detection - the one branch that
  # returns before reaching it - accepted `decode` and silently dropped it.
  fake <- structure(list(task = "object_detection", models = "y"), class = "platypus_fit")
  expect_error(predict(fake, decode = decode_watershed()), "instance model")
})


# ------------------------------------------------- a label that is a set, `#241`

test_that("labels_from is refused where the engine refuses it, before any interpreter starts", {
  # All four are the engine's own refusals, duplicated here for the reason the `subdirs` one
  # is: the sentence is the same and this way no Python starts in order to deliver it. They
  # have to be duplicated rather than forwarded because `platypus_spec()` sends a bare list
  # or a YAML file straight to the validator, so the two routes must agree.
  expect_error(
    classification_data("t/", "v/", classes = c("a", "b"), labels_from = c("A", "B")),
    "config_file"
  )
  expect_error(
    classification_data("t.csv", "v.csv", classes = c("a", "b"), labels_from = "A",
                        mode = "config_file"),
    "at least two"
  )
  expect_error(
    classification_data("t.csv", "v.csv", classes = c("a", "b"), labels_from = c("A", "B"),
                        mode = "config_file", strict_labels = FALSE),
    "nothing to choose between"
  )
  expect_error(
    classification_data("t.csv", "v.csv", classes = c("a", "b", "c"),
                        labels_from = c("A", "B"), mode = "config_file"),
    "paired by position"
  )
})

test_that("the three controls are accepted, or the refusals above prove nothing", {
  # A check calibrated loosely enough admits the failure it was written to prevent, and one
  # calibrated tightly enough fails on correct content. Both halves, every time.
  expect_no_error(
    classification_data("t.csv", "v.csv", classes = c("a", "b"), labels_from = c("A", "B"),
                        mode = "config_file")
  )
  expect_no_error(classification_data("t/", "v/", classes = c("a", "b")))
  expect_no_error(
    classification_data("t/", "v/", classes = c("a", "b"), strict_labels = FALSE)
  )
})

test_that("labels_from is dropped from the request when it is not given", {
  # §3D's rule: an option defaults to NULL and is left out, so an engine that does not know
  # the field keeps working for everybody not asking for it. Checked on the built list
  # rather than on the engine, because this is about what R sends.
  plain <- classification_data("t/", "v/", classes = c("a", "b"))
  expect_false("labels_from" %in% names(rplatypus:::compact(plain)))

  asked <- classification_data("t.csv", "v.csv", classes = c("a", "b"),
                               labels_from = c("A", "B"), mode = "config_file")
  expect_identical(rplatypus:::compact(asked)$labels_from, c("A", "B"))
})

test_that("a set of labels reaches the engine, and accuracy is refused beside it", {
  skip_if_no_engine()
  path <- tiny_multilabel_dataset()

  expect_identical(rplatypus:::spec_task(tiny_multilabel_spec(path)), "classification")

  # The engine's refusal, forwarded rather than restated: `metric_accuracy()` on a set is
  # exact match, and a model answering no to everything scores 0.8137 on it against 0.8023
  # for one holding half the signal, so no reading of it can be what a `monitor` watches.
  expect_error(
    tiny_multilabel_spec(path, metrics = list(metric_accuracy())),
    "accuracy"
  )
  # The control, and it is the one that matters: the same metric is admissible when the
  # label is a name, so the refusal is about the labelling and not about the metric.
  expect_no_error(
    tiny_multilabel_spec(path, metrics = list(metric_auc(), metric_f1()))
  )
})

test_that("predict() on a set of labels answers one row per image per class", {
  # The whole route, walked the way a reader of the help page would walk it, because green
  # on both halves proves the halves and not the join.
  skip_if_no_engine()
  path <- tiny_multilabel_dataset()
  fit <- platypus_fit(tiny_multilabel_spec(path), num_workers = 0)

  answers <- predict(fit, split = "validation")
  expect_identical(names(answers), c("key", "class", "label", "predicted"))
  expect_true(is.logical(answers$label) && is.logical(answers$predicted))
  expect_identical(nrow(answers), 24L)
  expect_identical(length(unique(answers$key)), 12L)

  # **The classes are `classes`, not the CSV's headers.** The file says `Bright` and `Wide`
  # and the specification says `bright` and `wide`; the engine pairs them by position, which
  # is the whole reason `labels_from` is a list rather than a flag, and a result carrying the
  # headers would make the class index depend on the file.
  expect_identical(sort(unique(answers$class)), c("bright", "wide"))

  # An image with neither finding is a row of FALSE per class rather than an absence. This
  # is the commonest row in a dataset shaped this way, and the one shape that cannot say
  # "unread" by accident.
  neither <- answers[answers$key == "case_0_00", ]
  expect_identical(nrow(neither), 2L)
  expect_false(any(neither$label))

  # And the truth in the frame is the truth in the file, read back from the CSV rather than
  # restated here - a test that writes its own expectation checks itself.
  written <- utils::read.csv(path)
  for (index in seq_len(nrow(written))) {
    row <- written[index, ]
    mine <- answers[answers$key == row$key, ]
    expect_identical(mine$label[mine$class == "bright"], row$Bright == 1L)
    expect_identical(mine$label[mine$class == "wide"], row$Wide == 1L)
  }
})

test_that("type = probability needs no branch for a set of labels", {
  # The `p_<class>` keys are in both shapes, so this path is the same code. Asserted rather
  # than assumed, because "it should still work" is how a shared path stops working.
  skip_if_no_engine()
  path <- tiny_multilabel_dataset()
  fit <- platypus_fit(tiny_multilabel_spec(path), num_workers = 0)

  chances <- predict(fit, split = "validation", type = "probability")
  expect_true(is.matrix(chances))
  expect_identical(dim(chances), c(12L, 2L))
  expect_identical(colnames(chances), c("bright", "wide"))
  expect_true(all(chances >= 0 & chances <= 1))
})

test_that("nobody said is NA and none of the findings is FALSE, in one frame", {
  # The distinction the long form was chosen for, and it only held while an unlabelled
  # classification split was unreachable. `0.8.0a52` made it reachable - a CSV of
  # `key, images` as `test_path`, which is what a prediction set looks like - and both
  # states reduce to `character(0)` on the way in, so `%in%` cannot tell them apart.
  #
  # One dataset, two splits, both halves asserted: either alone proves nothing. A test
  # showing NA where nobody labelled would pass just as well if FALSE had become NA
  # everywhere, which would be the same defect with the other sign.
  skip_if_no_engine()
  labelled <- tiny_multilabel_dataset()
  images_only <- tiny_unlabelled_csv(labelled)
  spec <- platypus_spec(
    data = classification_data(labelled, labelled, test = images_only,
                               classes = c("bright", "wide"),
                               labels_from = c("Bright", "Wide"),
                               mode = "config_file"),
    models = list(classifier("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                             epochs = 1, batch_size = 2))
  )
  fit <- platypus_fit(spec, num_workers = 0)

  unlabelled <- predict(fit, split = "test")
  expect_identical(names(unlabelled), c("key", "class", "label", "predicted"))
  expect_true(all(is.na(unlabelled$label)))
  expect_true(is.logical(unlabelled$label))
  # `predicted` is the model's own answer and is unaffected: there is nothing unknown
  # about what the model said.
  expect_false(any(is.na(unlabelled$predicted)))
  expect_identical(nrow(unlabelled), 2L * nrow(utils::read.csv(images_only)))

  # The other half, on the split that carries labels: a film with neither finding is FALSE
  # twice rather than NA, because that is a measured answer.
  scored <- predict(fit, split = "validation")
  neither <- scored[scored$key == "case_0_00", ]
  expect_identical(nrow(neither), 2L)
  expect_false(any(is.na(neither$label)))
  expect_false(any(neither$label))
  expect_false(any(is.na(scored$label)))
})

test_that("a split with no labelling has no balance to report", {
  # The engine's refusal, reaching an R user through the one function that forwards it.
  # `?class_balance` names `test` as a split to count and said nothing about this until
  # `0.8.0a52` made an unlabelled one reachable; counted anyway it reports every class at
  # zero, which reads as a finding about the dataset.
  skip_if_no_engine()
  labelled <- tiny_multilabel_dataset()
  images_only <- tiny_unlabelled_csv(labelled)
  spec <- platypus_spec(
    data = classification_data(labelled, labelled, test = images_only,
                               classes = c("bright", "wide"),
                               labels_from = c("Bright", "Wide"),
                               mode = "config_file"),
    models = list(classifier("tiny", input_shape = c(32, 32), blocks = 2, filters = 4,
                             epochs = 1, batch_size = 2))
  )

  expect_error(class_balance(spec, "test"), "no balance to report")
  # the control: the same call on a split that has labels answers
  counted <- class_balance(spec, "train")
  expect_identical(nrow(counted), 2L)
  expect_true(all(counted$n > 0))
})
