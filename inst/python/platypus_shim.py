"""The R-facing edge of the engine.

Exceptions do not survive the crossing usefully: reticulate hands R the message as text
and drops the object, so the structured problems pyplatypus reports would be lost and the
R side would be left parsing its own prose. Everything here therefore returns data.

This lives in the R package rather than in pyplatypus because it exists for R's benefit.
pyplatypus raises exceptions, like any Python library should.
"""

from __future__ import annotations

from typing import Any

#: The tasks whose engine does not take `check_masks`, by the `Task` enum's own values.
#: A detector has no masks and a classifier has one label per image, so there is nothing to
#: read a sample of - the option is dropped rather than sent and refused.
TASKS_WITHOUT_MASKS = ("object_detection", "classification")


def _failure(error: Any) -> dict:
    payload = error.to_dict() if hasattr(error, "to_dict") else {}
    payload.setdefault("kind", type(error).__name__)
    payload.setdefault("message", str(error))
    payload.setdefault("problems", [])
    payload["ok"] = False
    return payload


def _failure_message(message: str, kind: str = "engine_error") -> dict:
    """A failure this shim itself diagnosed, rather than one an exception described."""
    return {"ok": False, "kind": kind, "message": message, "problems": []}


def build_spec(config: dict, check_paths: bool = True) -> dict:
    """A validated spec, or the reasons it is not one."""
    import pyplatypus

    try:
        return {
            "ok": True,
            "spec": pyplatypus.from_dict(config, check_paths=check_paths),
        }
    except pyplatypus.PlatypusError as error:
        return _failure(error)


def load_spec(path: str, check_paths: bool = True) -> dict:
    """The same, from a YAML file. The same object comes out either way."""
    import pyplatypus

    try:
        return {"ok": True, "spec": pyplatypus.from_yaml(path, check_paths=check_paths)}
    except pyplatypus.PlatypusError as error:
        return _failure(error)


def spec_as_dict(spec: Any) -> dict:
    """Plain data, so R can look at a spec without asking Python about every field."""
    return spec.to_dict()


def _engine_failure(error: Any) -> dict:
    """A failure during a run, rather than in a specification.

    Caught broadly on purpose. A specification error is ours and arrives well described;
    a run can fail on anything underneath - the GPU running out of memory, a file that
    vanished, a driver that cannot do what the build expects - and those exceptions come
    from libraries the user never invoked. Letting them through as a reticulate traceback
    would be the least useful moment possible to stop being readable, because it happens
    after the expensive part. The type is kept in the message so it stays diagnosable.
    """
    return {
        "ok": False,
        "kind": "engine_error",
        "message": f"{type(error).__name__}: {error}",
        "problems": [],
    }


def build_engine(
    spec: Any,
    device: str | None = None,
    num_workers: int = 0,
    strict_data: bool = True,
    check_masks: bool = True,
) -> dict:
    import pyplatypus

    options = {}
    # Passed only when it is not the default, so this shim keeps working against an engine
    # that predates the argument - which is the same rule the R options follow.
    if not check_masks:
        options["check_masks"] = False

    # `build_engine` picks the engine the spec's task asks for. A detector has no masks to
    # check and neither has a classifier, so the option is dropped rather than sent and
    # refused: it is meaningless there, not disallowed.
    maker = getattr(pyplatypus, "build_engine", None)
    if maker is None:
        return _failure_message(
            "This engine predates `build_engine`, so it cannot tell a detection "
            "specification from a segmentation one. Update platypus, or point "
            "PLATYPUS_ENGINE_PATH at a newer source tree."
        )
    # The VALUES rather than the words they shorten to, which is the whole of why this
    # line is written out: the comparison read `== "detection"` while the enum member is
    # `Task.OBJECT_DETECTION` with the value `"object_detection"`, so it never fired. The
    # cost was not a missing drop - it was the wrong diagnosis: `check_masks=False` reached
    # `DetectionEngine`, which has no such argument, and the `TypeError` below reports
    # "this engine predates `check_masks`" about an engine that is current. Classification
    # is the second task in this position and `ClassificationEngine` takes no such argument
    # either, so both are named here and `tests/testthat/test-shim-mask-option.R` holds the
    # set against the engines' own signatures rather than against this comment.
    if getattr(getattr(spec, "task", None), "value", None) in TASKS_WITHOUT_MASKS:
        options.pop("check_masks", None)

    try:
        engine = maker(
            spec,
            device=device,
            num_workers=int(num_workers),
            strict_data=strict_data,
            **options,
        )
    except TypeError as error:
        if "check_masks" in str(error):
            return _failure_message(
                "This engine predates `check_masks`, so the check cannot be turned off. "
                "Correct the colormap or labels instead, or update platypus."
            )
        return _engine_failure(error)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001 - see _engine_failure
        return _engine_failure(error)
    return {"ok": True, "engine": engine}


def inspect_masks(spec: Any, split: str = "train", limit: int = 500) -> dict:
    """What the colormap or labels match in one split's masks, over `limit` samples.

    The engine reads a small sample before training and refuses when a declared class
    appears in none of it. This is the same question asked deliberately and over as much
    of the data as wanted - which is what the refusal tells someone to do next, and it has
    to be reachable from R or the advice is worthless.
    """
    import pyplatypus

    try:
        engine = pyplatypus.Engine(spec, check_masks=False)
        model = spec.models[0]
        report = engine.dataset(model, split).inspect_masks(limit=int(limit))
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001 - see _engine_failure
        return _engine_failure(error)
    return {
        "ok": True,
        "unmatched": float(report.unmatched),
        "present_classes": [int(c) for c in report.present_classes],
        "missing_classes": [int(c) for c in report.missing_classes],
        "samples_checked": int(report.samples_checked),
        "total_samples": int(report.total_samples),
    }


def run_fit(engine: Any, verbose: bool = False) -> dict:
    """Train every model, and hand back the history as rows rather than objects."""
    import pyplatypus

    try:
        histories = engine.fit(verbose=bool(verbose))
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    rows, reasons = [], {}
    for name, history in histories.items():
        for record in history.records:
            rows.append({"model": name, **record})
        if history.stop_reason:
            reasons[name] = history.stop_reason
    return {
        "ok": True,
        "history": rows,
        "stop_reasons": reasons,
        "models": list(histories),
    }


def evaluation_table(engine: Any, split: str = "validation", at: str | None = None) -> dict:
    """The comparison table. `at` picks the grid and is omitted when R did not ask.

    Omitted rather than defaulted here: the engine owns what unset means, and sending
    `at="model"` from R would make this file a second place the default lives.
    """
    import pyplatypus

    try:
        extra = {} if at is None else {"at": str(at)}
        return {"ok": True, "table": engine.evaluate(split, **extra)}
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)


def predictions(
    engine: Any,
    model_name: str,
    split: str = "test",
    as_class: bool = True,
    space: str = "model",
) -> dict:
    """Masks for a split.

    `as_class` collapses the channel axis to the class index, which is the mask someone
    actually wants to look at; the probabilities are there for anyone who needs them.

    `space` is `"model"` or `"source"`. In source space the engine returns one array per scan,
    on that scan's own grid, so the result is a list - which is why the answer says which space
    it is in rather than leaving R to infer it from the shape.
    """
    import numpy as np
    import pyplatypus

    def to_class(array):
        # +1 so the classes are 1-based on arrival: R indexes from one, and a mask whose
        # background is 0 while its colormap starts at 1 is a trap laid for later.
        return (array.argmax(axis=-1) + 1).astype(np.int32)

    if space == "source":
        # Source space: one array per scan, each on its own grid, so this cannot become one
        # array and R receives a list. Keeping the shapes apart is the point - see
        # `?predict.platypus_fit`.
        #
        # Taken from `predict_stream` rather than from `engine.predict`, and the reason is
        # the NAMES. `predict` returns the arrays alone, so R used to hand back a list a
        # caller had to pair against case names by position - which that same help page
        # argues against two lines above the sentence documenting this return, and which
        # the instance path already avoids. `maju116/rplatypus#223`.
        #
        # One pass, not two. A name and a mask that come out of the same `next()` cannot be
        # misaligned, where a second call to list the split is one `drop_last` from being
        # off by one - and would also run the model over the split again.
        cases: list[str] = []
        masks = []
        try:
            for case, probabilities in engine.predict_stream(model_name, split=split, space=space):
                cases.append(case)
                masks.append(to_class(probabilities) if as_class else probabilities)
        except pyplatypus.PlatypusError as error:
            return _failure(error)
        except Exception as error:  # noqa: BLE001
            return _engine_failure(error)
        return {
            "ok": True,
            "masks": masks,
            "cases": cases,
            "type": "class" if as_class else "probability",
            "space": "source",
        }

    try:
        probabilities = engine.predict(model_name, split=split, space=space)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    # Model space is one stacked array rather than a list, so there is nothing to name: the
    # asymmetry this function carries is between the two SPACES, not between two tasks.
    masks = to_class(probabilities) if as_class else probabilities
    return {
        "ok": True,
        "masks": masks,
        "type": "class" if as_class else "probability",
        "space": "model",
    }


def predictions_each(
    engine: Any,
    model_name: str,
    visit: Any,
    split: str = "test",
    as_class: bool = True,
    space: str = "model",
    cases: Any = None,
) -> dict:
    """One mask at a time, handed to `visit`, instead of a whole split at once.

    `predictions` above returns the lot, which for a tiled run is the whole split at full
    resolution - 6.7 GB for 200 retinas at 2048, and the engine's own `predict` was killed
    by exactly that. This walks `predict_stream` and calls `visit(case, mask)` per image, so
    nothing is held but the one being looked at and whatever the caller decides to keep.

    `cases` names the ones wanted; everything else is decoded, predicted and dropped. The
    stream is sequential, so asking for two of two hundred still runs the model over two
    hundred - the saving is in memory, not in time. Said here because a caller who wanted
    the other saving would need the engine to skip, which it cannot yet.

    `visit` is called **outside** the guard below on purpose. It is the caller's own
    function, and an error in it is theirs: wrapping it would report an R bug as an engine
    failure, which is the kind of mislabelling that costs an afternoon.
    """
    import numpy as np
    import pyplatypus

    wanted = None if cases is None else {str(case) for case in cases}

    def to_class(array):
        # +1 for the same reason as in `predictions`: R indexes from one.
        return (array.argmax(axis=-1) + 1).astype(np.int32)

    try:
        stream = engine.predict_stream(model_name, split=split, space=space)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    delivered: list[str] = []
    while True:
        try:
            case, probabilities = next(stream)
        except StopIteration:
            break
        except pyplatypus.PlatypusError as error:
            return _failure(error)
        except Exception as error:  # noqa: BLE001
            return _engine_failure(error)

        if wanted is not None and case not in wanted:
            continue
        visit(case, to_class(probabilities) if as_class else probabilities)
        delivered.append(case)

    missing = sorted(wanted - set(delivered)) if wanted is not None else []
    if missing:
        return _failure_message(
            f"no case called {', '.join(repr(name) for name in missing)} in '{split}'; "
            "a name that is not there would otherwise come back as an empty result",
            kind="unknown_case",
        )
    return {
        "ok": True,
        "cases": delivered,
        "type": "class" if as_class else "probability",
        "space": space,
    }


# ---------------------------------------------------------------------- detection


def detections(engine: Any, model_name: str, split: str = "test") -> dict:
    """Boxes for a split, one entry per image, in each image's own pixels.

    Not masks, and not an array. Images differ in size and so does the number of boxes
    found in each, so this is a list - and the boxes are in the coordinates of the file
    they came from rather than the network's letterboxed frame, because that is where a
    person can draw them.

    Labels arrive **1-based**, like the class indices `predictions` returns: R indexes
    from one, and a label whose first class is 0 while `classes` starts at 1 is a trap
    laid for later. `names` comes along so nothing downstream has to do the lookup.
    """
    import numpy as np
    import pyplatypus

    try:
        found = engine.predict(model_name, split=split)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    out = []
    for entry in found:
        out.append(
            {
                "key": entry["key"],
                "boxes": np.asarray(entry["boxes"], dtype=float).reshape(-1, 4),
                "scores": np.asarray(entry["scores"], dtype=float).reshape(-1),
                "labels": (np.asarray(entry["labels"], dtype=np.int32) + 1).reshape(-1),
                "names": list(entry["names"]),
            }
        )
    return {"ok": True, "detections": out}


def detection_table(engine: Any, split: str = "validation") -> dict:
    """One row per model, with detection's columns."""
    import pyplatypus

    try:
        return {"ok": True, "table": engine.evaluate(split)}
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)


def detection_classes(engine: Any, model_name: str, split: str = "validation") -> dict:
    """One row per class, which is the row that matters on unbalanced data."""
    import pyplatypus

    try:
        return {"ok": True, "rows": engine.evaluate_classes(model_name, split)}
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)


def detection_images(
    engine: Any, model_name: str, split: str = "validation", score_threshold: Any = None
) -> dict:
    """One row per image: which pictures it fails on, rather than how well on average."""
    import pyplatypus

    try:
        return {
            "ok": True,
            "rows": engine.evaluate_images(model_name, split, score_threshold=score_threshold),
        }
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)


def detection_crops(
    engine: Any,
    model_name: str,
    split: str = "test",
    score_threshold: Any = None,
    context: float = 0.0,
    size: Any = None,
    fit: str = "letterbox",
) -> dict:
    """Every detection cut out of the image it was found in, one record per image.

    The arrays cross the bridge as they are: reticulate turns each into an R array with the
    axes it already has, height x width x channels, which is the orientation every plotting
    helper in the R package already expects. Nothing is stacked, because the crops of one
    image differ in size unless `size` was given and the number of them differs per image
    regardless - and a stack that needed a silent resize to exist is the thing the
    segmentation side refuses for the same reason.

    `dropped` comes through per record. A model may place a box off the frame and `predict`
    reports what it said, so some boxes clip to nothing; the engine drops those and counts
    them, and hiding the count would leave the arrays silently shorter than the detections.
    """
    import pyplatypus

    try:
        records = engine.crops(
            model_name,
            split,
            score_threshold=score_threshold,
            context=context,
            size=None if size is None else (int(size[0]), int(size[1])),
            fit=fit,
        )
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    return {
        "ok": True,
        "records": [
            {
                "key": record["key"],
                "crops": list(record["crops"]),
                "boxes": record["boxes"],
                "scores": record["scores"],
                # +1 so the classes are 1-based on arrival, as everywhere else here.
                "labels": (record["labels"] + 1).tolist(),
                "names": list(record["names"]),
                "dropped": int(record["dropped"]),
            }
            for record in records
        ],
    }


def anchor_report(engine: Any, model_name: str, split: str = "train") -> dict:
    """How well the anchors in use cover a split's boxes.

    Worth asking of a split they were *not* fitted on: 0.92 on training and 0.70 on
    validation says the two hold different objects, and no training curve shows that.
    """
    import pyplatypus

    try:
        return {"ok": True, "coverage": engine.anchor_coverage(model_name, split)}
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)


def run_anchors(engine: Any, model_name: str) -> dict:
    """The anchors a run used, and whether they were fitted or given.

    A detector cannot be reloaded without them, so this is how R gets at the only record
    when they were fitted rather than named in the specification.
    """
    try:
        run = engine.runs[model_name]
    except KeyError:
        known = ", ".join(engine.runs) or "none"
        return _failure_message(f"no model called '{model_name}'; trained so far: {known}")
    fitted = run.anchor_fit
    return {
        "ok": True,
        "anchors": [[list(pair) for pair in group] for group in run.anchors],
        "fitted": fitted is not None,
        "mean_iou": None if fitted is None else float(fitted.mean_iou),
        "boxes_used": None if fitted is None else int(fitted.boxes_used),
        "rows": [] if fitted is None else fitted.as_rows(),
    }


def anchor_shapes(engine: Any, model_name: str, split: str = "train") -> dict:
    """The cloud of box shapes in a split, with the anchors in use beside it.

    Both in one set of coordinates, from one call, because the alternative - widths from
    one place and anchors from another - is how a picture comes to show boxes in different
    places from where the anchors were fitted to them.
    """
    import pyplatypus

    if not hasattr(engine, "box_shapes"):
        return _failure_message(
            "This engine predates the anchor plot. Update platypus, or point "
            "PLATYPUS_ENGINE_PATH at a newer source tree."
        )
    try:
        return {"ok": True, **engine.box_shapes(model_name, split)}
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)


def target_survey(engine: Any, model_name: str) -> dict:
    """What the target could and could not hold, measured before training."""
    try:
        run = engine.runs[model_name]
    except KeyError:
        return _failure_message(f"no model called '{model_name}'")
    if run.survey is None:
        return _failure_message(
            f"'{model_name}' was not trained, so its targets were never surveyed."
        )
    return {"ok": True, "survey": run.survey.to_dict()}


def drawing_style() -> dict:
    """The engine's drawing decisions, for the test that holds R's copy to them.

    Not used when drawing: R mirrors these values so that `plot_masks()` and the rest need
    no Python at all. This is what makes the mirror a mirror - if the engine changes a
    colour and R does not, the comparison in `test-drawing-style.R` fails.
    """
    import pyplatypus

    if not hasattr(pyplatypus, "drawing_style"):
        return _failure_message(
            "This engine predates the shared drawing style. Update platypus, or point "
            "PLATYPUS_ENGINE_PATH at a newer source tree."
        )
    return {"ok": True, "style": pyplatypus.drawing_style()}


def model_names(engine: Any) -> list:
    return list(engine.runs)


def device_report() -> dict:
    """What the engine says about where the work will happen.

    A forward since `0.8.0a38`. This function used to own the answer - it asked torch
    about the version, the build, the card and whether one was present but unusable - and
    that was the wrong side of the bridge: a Python user could not reach any of it, so
    the half of this family with more users was the half that could not be told.

    What stays in R is the *advice*: `print.platypus_device()` says to call
    `platypus_use_torch("pascal")`, which is a sentence about R's session model and means
    nothing to somebody who installed the engine with pip. Their version of it is "install
    the pascal extra", and it belongs with the engine.
    """
    import pyplatypus

    return pyplatypus.device_report()


def read_images(
    paths: list, channels: int = 3, size: list | None = None, nearest: bool = False
) -> dict:
    """Read images exactly as the data pipeline would.

    Not a convenience: a picture plotted from a differently resized copy is a picture of
    something the model never saw, and the disagreements it shows may be the resizing.
    """
    import numpy as np
    from pyplatypus.data import read_image

    try:
        arrays = [
            read_image(
                p,
                channels=int(channels),
                size=tuple(int(s) for s in size) if size else None,
                nearest=bool(nearest),
            )
            for p in paths
        ]
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    shapes = {a.shape for a in arrays}
    if len(shapes) > 1 and size is None:
        return {
            "ok": False,
            "kind": "image_error",
            "problems": [],
            "message": (
                "these images are not all the same size "
                f"({', '.join('x'.join(map(str, s)) for s in sorted(shapes))}), so they "
                "cannot go into one array. Pass `size` to read them at a common size."
            ),
        }
    return {"ok": True, "images": np.stack(arrays)}


def write_masks(masks, paths: list) -> dict:
    """Write coloured masks to the given files.

    Through the engine rather than through an R image library, for the same reason as
    reading: one decoder, one set of conventions, and no extra dependency on the R side
    for something the engine can already do.
    """
    import pathlib

    import numpy as np
    from PIL import Image

    try:
        arrays = np.asarray(masks, dtype=np.uint8)
        if arrays.ndim == 3:
            arrays = arrays[None]
        if len(arrays) != len(paths):
            return {
                "ok": False,
                "kind": "image_error",
                "problems": [],
                "message": f"{len(arrays)} masks but {len(paths)} paths",
            }
        for array, path in zip(arrays, paths):
            target = pathlib.Path(path)
            target.parent.mkdir(parents=True, exist_ok=True)
            Image.fromarray(array).convert("RGB").save(target)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "paths": [str(p) for p in paths]}


def instance_predictions(
    engine: Any,
    model_name: str,
    split: str = "test",
    decode: Any = None,
) -> dict:
    """One label map per image, named by the case it came from.

    `predict_instances` returns a bare list in the split's order, and a list paired against
    a sequence of case names by position is one `drop_last` away from naming the wrong
    picture - the mistake `predict_stream` exists on the semantic side to avoid. So the keys
    are read here, from **the same two objects the engine pairs internally**: its own
    `evaluate_cases` walks `predict_stream` with `enumerate` and takes
    `dataset.samples[index].key`, which is what this does without re-running the model.

    `decode` picks the decoding by name; unset takes the model's first, which is the
    engine's own default and not one restated here.
    """
    import numpy as np
    import pyplatypus

    try:
        maps = engine.predict_instances(
            model_name, split=split, decode=None if decode is None else str(decode)
        )
        run = engine.runs[model_name]
        keys = [sample.key for sample in engine.dataset(run.spec, split).samples]
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    if len(keys) != len(maps):
        # Not a guard against the engine being wrong - it is a guard against this function
        # being wrong about which dataset it asked. Tiling makes a loader longer than its
        # samples, and if that ever reached here the names would silently slide by one.
        return _failure_message(
            f"the engine returned {len(maps)} label maps and the split names {len(keys)} "
            "cases, so naming them by position would name the wrong pictures"
        )
    return {
        "ok": True,
        "cases": list(keys),
        "maps": [np.asarray(one, dtype=np.int32) for one in maps],
        "decodings": [block.name for block in engine.runs[model_name].spec.decodings],
    }


def instance_channels(engine: Any, model_name: str, split: str = "test") -> dict:
    """The model's own channels, raw, which is what a flow field has to be read from.

    Deliberately separate from `instance_predictions`: these are not probabilities. The
    class channels are, and the vector channels are **raw** - a softmax across a flow
    component and a class would return a number and mean nothing - so the two cannot be one
    call with a flag.
    """
    import numpy as np
    import pyplatypus

    try:
        channels = engine.predict(model_name, split=split)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "channels": np.asarray(channels)}


def classification_answers(engine: Any, model_name: str, split: str = "test") -> dict:
    """One row per image: its key, its label, the answer and every class's probability.

    `engine.answers()` rather than `engine.predict()`, and the difference is the key. A
    bare array of probabilities has to be paired with the split's samples by position,
    which is one `drop_last` away from naming the wrong picture - `rplatypus#223` is that
    defect on the semantic side and there is no reason to ship it again one task across.
    Both shapes R offers are built from these rows, so the keys and the class order are
    read once.
    """
    import pyplatypus

    try:
        rows = engine.answers(model_name, split=split)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {
        "ok": True,
        "rows": rows,
        # The class order is the specification's, not the columns' - a row's `p_` keys are
        # built from it, but reading them back off a dict would hand R whatever order the
        # mapping iterated in.
        "classes": list(engine.spec.data.classes),
        # Read off the specification rather than sniffed off a row. The two shapes differ by
        # which keys they carry - a set of labels has `labels` and no `probability` - so R
        # could infer it, and an inference from a shape is one release away from being wrong
        # about a shape that gained a key. `multilabel` is the property the whole engine
        # reads this from, derived from the naming, which is the thing that carries the
        # claim.
        "multilabel": bool(engine.spec.data.multilabel),
    }


def class_balance(spec: Any, split: str = "train") -> dict:
    """How many images each class has in a split, before anything is trained.

    Built with `strict_data=False` so that a count can be taken of data that is not yet
    tidy: the question "what have I got" is exactly the one somebody asks when a split is
    still wrong, and refusing to answer it until the data is perfect would make this
    useless where it is most wanted.

    `remark` is the engine's own sentence rather than the numbers re-read on R's side. The
    threshold it fires below is the engine's number, and a copy of it in R would be a second
    place for one fact to live.
    """
    import pyplatypus

    try:
        engine = pyplatypus.build_engine(spec, strict_data=False)
        balance = engine.balance(split)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {
        "ok": True,
        "counts": {str(name): int(count) for name, count in balance.counts.items()},
        "remark": str(balance),
    }


def class_masks(
    prediction,
    directory: str,
    classes: list,
    cases: list | None = None,
    threshold: float = 0.5,
    suffix: str = "",
) -> dict:
    """One file per class, through the engine's own writer.

    Forwarding rather than reimplementing. The filenames, the threshold and every refusal
    live in `pyplatypus.save_class_masks`, so the two packages cannot disagree about what a
    region is called on disk - and the filenames are part of what a user's next script
    reads, which makes them a contract rather than a detail.

    Added for `0.8.0a23`, which is the release that writer arrived in; against an older
    engine the call fails by name here rather than producing half of it.
    """
    import numpy as np
    import pyplatypus

    if not hasattr(pyplatypus, "save_class_masks"):
        return _failure_message(
            "this engine has no `save_class_masks`; one file per class arrived in "
            f"pyplatypus 0.8.0a23 and the engine in use is {pyplatypus.__version__}"
        )
    try:
        paths = pyplatypus.save_class_masks(
            np.asarray(prediction, dtype=np.float32),
            directory,
            classes=[str(name) for name in classes],
            cases=None if cases is None else [str(case) for case in cases],
            threshold=float(threshold),
            suffix=str(suffix),
        )
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "paths": [str(path) for path in paths]}


def write_class_volumes(
    prediction,
    directory: str,
    reference: list,
    classes: list,
    cases: list | None = None,
    threshold: float = 0.5,
    suffix: str = "",
) -> dict:
    """One volume per class, through the engine's own writer.

    Forwarding rather than reimplementing, exactly as `write_class_masks` does one
    dimension down. Until `0.8.0a29` there was nowhere to forward to: this package carried
    `write_volumes` with its own logic, and R computed the per-class filenames itself, so
    the rule for turning `whole tumour` into a filename existed twice and a test had to
    hold the two together. The engine owns both now.

    Added for `0.8.0a29`; against an older engine the call fails by name here rather than
    producing half of it.
    """
    import numpy as np
    import pyplatypus

    if not hasattr(pyplatypus, "save_class_volumes"):
        return _failure_message(
            "this engine has no `save_class_volumes`; one volume per class arrived in "
            f"pyplatypus 0.8.0a29 and the engine in use is {pyplatypus.__version__}"
        )
    try:
        paths = pyplatypus.save_class_volumes(
            [np.asarray(one, dtype=np.float32) for one in prediction],
            directory,
            reference=[str(path) for path in reference],
            classes=[str(name) for name in classes],
            cases=None if cases is None else [str(case) for case in cases],
            threshold=float(threshold),
            suffix=str(suffix),
        )
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "paths": [str(path) for path in paths]}


def window_presets() -> dict:
    """The named CT windows, so R does not keep its own copy to drift out of step."""
    from pyplatypus.spec.common import WINDOWS

    return {name: list(pair) for name, pair in WINDOWS.items()}


def split_data(
    root: str,
    out_dir: str,
    mode: str = "nested_dirs",
    subdirs: list | None = None,
    column_sep: str = ";",
    fractions: list | None = None,
    group_by: str | None = None,
    seed: int = 0,
    strict: bool = True,
    relative: bool = True,
) -> dict:
    """Divide one directory into train/validation/test CSVs.

    `group_by` crosses over as written, on purpose. It is a Python regular expression, and
    translating patterns between R and Python in the background is a silent failure waiting
    to happen: the two dialects agree often enough to lull, and differ exactly where it
    matters. Documented in ?platypus_split instead.
    """
    import pyplatypus

    try:
        report = pyplatypus.split_dataset(
            root,
            out_dir,
            mode=mode,
            subdirs=tuple(subdirs) if subdirs else ("images", "masks"),
            column_sep=column_sep,
            fractions=tuple(float(f) for f in fractions) if fractions else (0.7, 0.15, 0.15),
            group_by=group_by,
            seed=int(seed),
            strict=bool(strict),
            relative=bool(relative),
        )
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, **report}


def case_table(
    engine: Any,
    model_name: str,
    split: str = "validation",
    group_by: str | None = None,
    at: str | None = None,
) -> dict:
    """One row per case - or per group, with `group_by` - instead of one per model."""
    import pyplatypus

    try:
        extra = {} if at is None else {"at": str(at)}
        rows = engine.evaluate_cases(model_name, split=split, group_by=group_by, **extra)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "table": rows, "label": "group" if group_by else "case"}


def case_summary(rows: list) -> dict:
    """The distribution of the per-case scores.

    Computed by the engine rather than in R although it is only means and quantiles: two
    implementations of the same summary would eventually disagree, and a table that differs
    between the R and Python surfaces is worse than no table.
    """
    import pyplatypus

    try:
        return {"ok": True, "table": pyplatypus.summarise_cases(list(rows))}
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)


def volume_support() -> bool:
    """Whether the engine in use can read volumes at all."""
    try:
        from pyplatypus.data import volumes  # noqa: F401
    except Exception:  # noqa: BLE001
        return False
    return True


def volume_info(paths: list) -> dict:
    """Shape and voxel spacing for each volume, in the canonical order the reader uses.

    Spacing is not decoration. A segmented lesion counted in voxels is a number that means
    nothing outside the scanner it came from; the same count times the voxel volume is
    millilitres, which is what a report says and what a clinician compares.
    """
    from pyplatypus.data.volumes import VolumeError, read_volume, volume_spacing

    rows = []
    try:
        for path in paths:
            spacing = volume_spacing(path)
            shape = read_volume(path, nearest=True).shape
            rows.append(
                {
                    "path": str(path),
                    "spacing": list(spacing),
                    "shape": list(shape[:3]),
                    "voxel_ml": float(spacing[0] * spacing[1] * spacing[2] / 1000.0),
                }
            )
    except VolumeError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "volumes": rows}


def ellipse_measurement(mask, spacing) -> dict:
    """The ellipse a region implies: its semi-axes and its circumference, in one crossing.

    Both numbers rather than two functions, because they come from the same second moments
    and a reader wanting a biometry row wants all three figures together. The engine's
    `ellipse_axes` and `ellipse_circumference` are separate there for the same reason this
    is one here: there, a caller composing them pays nothing; here, each call is a crossing.

    **The mask arriving is already boolean**, converted on the R side. The engine reads a
    foreground as `> 0`, which is right for its own `argmax` maps and silently wrong for
    this package's: `which.max` writes 1 for background, so `> 0` would be every pixel of
    every image. R does `mask == class` before sending, and that is why these take no class
    argument.
    """
    from pyplatypus.measure import MeasureError, ellipse_axes, ellipse_circumference

    sides = None if spacing is None else [float(side) for side in spacing]
    try:
        major, minor = ellipse_axes(mask, sides)
        around = ellipse_circumference(mask, sides)
    except MeasureError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "major": float(major), "minor": float(minor), "around": float(around)}


def instance_shape_rows(labels, spacing) -> dict:
    """Per-object shape out of one label map, as columns rather than as rows.

    Columns, because the row set has a varying key set - `middle_mm` only for a volume,
    `eccentricity` only for an image, `_px` instead of `_mm` without a spacing - and a list
    of dicts with different keys does not become a data frame on the other side without R
    guessing. `names` carries the order explicitly rather than relying on a Python dict's
    insertion order surviving the crossing, which is a property nothing here tests.

    **The label map arrives as the engine numbers one**: 0 for background, an integer per
    object. That is also how this package's instance predictions are numbered, so unlike
    `ellipse_measurement` this takes no class argument - there is no asymmetry to correct.
    """
    from pyplatypus.measure import MeasureError, instance_shapes

    sides = None if spacing is None else [float(side) for side in spacing]
    try:
        rows = instance_shapes(labels, sides)
    except MeasureError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    # The key set comes from the first row rather than from the rank and the spacing, so
    # that R is told what the engine actually answered instead of what this function
    # predicts it would. An empty map has no first row and no columns to name.
    names = list(rows[0]) if rows else []
    columns = {
        name: [int(row[name]) if name == "object" else float(row[name]) for row in rows]
        for name in names
    }
    return {"ok": True, "names": names, "columns": columns, "objects": len(rows)}


def write_volumes(masks, paths: list, reference: list) -> dict:
    """Label-map volumes as NIfTI, through the engine's own writer.

    Forwarding rather than reimplementing, which it could not do until `0.8.0a29` put a
    volume writer in the engine and `0.8.0a30` taught it to take a label map. Until then
    this function carried its own nibabel loop, and the affine decision - that a mask is
    written against the reference read the way the reader reads it, canonical rather than
    stored - existed in two places. It is the engine's now.

    **Label maps rather than channels, and that is deliberate.** This package collapses a
    prediction with `which.max`, so its class indices are counted from 1 and every file it
    has ever written carries 1 and 2 where the engine's `argmax` would write 0 and 1.
    Handing the engine the channel form instead would silently change the values in every
    mask this package produces, so the collapse stays here and the engine writes what it is
    given.

    `paths` rather than a directory and names: this package has always chosen the whole
    path, including its refusal when two would collide, and the engine's `cases` argument
    is a different spelling of the same decision - so the paths are split back into a
    directory and stems here rather than letting the two disagree about either.
    """
    import pathlib

    import numpy as np
    import pyplatypus

    if not hasattr(pyplatypus, "save_volumes"):
        return _failure_message(
            "this engine has no `save_volumes`; writing a volume arrived in pyplatypus "
            f"0.8.0a29 and the engine in use is {pyplatypus.__version__}"
        )
    targets = [pathlib.Path(path) for path in paths]
    directories = {path.parent for path in targets}
    if len(directories) != 1:
        return _failure_message(
            "the masks would be written to several directories, and one call writes to one"
        )
    try:
        written = pyplatypus.save_volumes(
            [np.asarray(one) for one in masks],
            directories.pop(),
            reference=[str(path) for path in reference],
            cases=[path.name.removesuffix(".nii.gz") for path in targets],
        )
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "paths": [str(path) for path in written]}


def series_report(paths: list) -> dict:
    """Check each directory of DICOM slices and report what is wrong with it.

    One row per directory, and a problem is a value in a column rather than an exception. A
    hundred cases out of an archive will contain a few with a missing slice, two series in one
    folder, or duplicated files, and stopping at the first one means looking at them one at a
    time for an afternoon. The point of this function is the list.

    No pixels are read: every check here runs on headers, so this stays usable on a hundred
    gigabytes of data.
    """
    from pyplatypus.data.dicom_series import describe_series
    from pyplatypus.errors import PlatypusError

    rows = []
    for path in paths:
        row = {
            "path": str(path),
            "ok": False,
            "slices": 0,
            "sorted_by": None,
            "spacing": None,
            "series_uid": None,
            "problem": None,
        }
        try:
            series = describe_series(path)
        except PlatypusError as error:
            row["problem"] = str(error)
        except Exception as error:  # noqa: BLE001
            row["problem"] = f"{type(error).__name__}: {error}"
        else:
            row.update(
                {
                    "ok": True,
                    "slices": len(series),
                    "sorted_by": series.sorted_by,
                    "spacing": list(series.spacing),
                    "series_uid": series.series_uid,
                    "shape": list(series.shape),
                }
            )
        rows.append(row)
    return {"ok": True, "series": rows}


def series_support() -> bool:
    try:
        from pyplatypus.data import dicom_series  # noqa: F401
    except Exception:  # noqa: BLE001
        return False
    return True


def transform_names(rank: int = 2) -> dict:
    """Which albumentations transforms can be used, at this rank.

    For volumes the list has to be found by trying rather than read from anywhere: support is
    uneven and a transform that cannot take a volume raises from inside the library, which is
    why the engine probes. Slow enough to be worth doing once, so it is cached there.
    """
    import pyplatypus

    try:
        from pyplatypus import available_transforms
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    try:
        names = sorted(available_transforms(rank=int(rank)))
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "transforms": names, "rank": int(rank)}


def component_listing(kind: str, task: str | None = None) -> dict:
    """One of the engine's `available_*` listings, as rows R can make a data frame of.

    One function rather than six, because the R side differs only in which name it passes
    and the engine is the thing that knows what each listing contains. `arguments` comes
    back as a list and R joins it: a data frame cell holding a vector prints as a column
    nobody can read.

    A refusal is a refusal with a message - `available_metrics(task="object_detection")`
    raises rather than returning an empty table, and that message is the answer, so it
    crosses the bridge as a condition instead of being flattened into zero rows.
    """
    import pyplatypus

    try:
        listing = getattr(pyplatypus, f"available_{kind}")
    except AttributeError as error:  # an engine older than 0.8.0a11
        return _engine_failure(error)

    try:
        rows = listing() if task is None else listing(task)
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)

    # `needs` and `head_channels` belong to two listings only and are the reason somebody
    # asks for those listings at all: which separation a decoding requires, and how wide a
    # head a separation makes. Carried when the engine's row has them rather than named
    # here, so a listing that grows a field reaches R without this function changing.
    extra = ("needs", "head_channels")
    return {
        "ok": True,
        "rows": [
            {
                "name": row["name"],
                "arguments": ", ".join(row.get("arguments", row.get("chooses", ()))),
                "description": row["description"],
                **{
                    key: ", ".join(row[key]) if isinstance(row[key], tuple | list) else row[key]
                    for key in extra
                    if key in row
                },
            }
            for row in rows
        ],
    }


def save_spec(spec: Any, path: str, defaults: bool = False) -> dict:
    """Write a specification back out as YAML.

    The engine writes what was *set* rather than what the object holds, and that is the
    whole point of it: a model given `weights` and no `architecture` adopts the architecture
    from the weights sidecar, and the adoption fires on the field not having been set.
    """
    import pyplatypus

    try:
        from pyplatypus import save_spec as write
    except Exception as error:  # noqa: BLE001 - an engine older than 0.8.0a11
        return _engine_failure(error)

    try:
        written = write(spec, path, defaults=bool(defaults))
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    return {"ok": True, "path": str(written)}


def weights_listing() -> dict:
    """The published weights and what each one is."""
    import pyplatypus

    try:
        from pyplatypus.weights import REGISTRY
    except Exception as error:  # noqa: BLE001 - an engine older than the registry
        return _engine_failure(error)

    try:
        rows = [
            {
                "name": name,
                "repo": entry.repo,
                "filename": entry.filename,
                "revision": entry.revision,
                "description": entry.description,
            }
            for name, entry in sorted(REGISTRY.items())
        ]
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    return {"ok": True, "weights": rows}


def export_weights(engine: Any, model_name: str, path: str, extra: dict | None = None) -> dict:
    """Write one trained model's weights, with the sidecar describing them."""
    import pyplatypus

    try:
        written = engine.export_weights(model_name, path, **(extra or {}))
    except pyplatypus.PlatypusError as error:
        return _failure(error)
    except Exception as error:  # noqa: BLE001
        return _engine_failure(error)
    import json

    sidecar = written.with_suffix(".json")
    # The contents as well as the path. R has no JSON reader of its own here, and adding a
    # dependency so that a caller can see what was recorded would be a poor trade: the engine
    # already has the data in hand.
    return {
        "ok": True,
        "path": str(written),
        "sidecar": str(sidecar),
        "recorded": json.loads(sidecar.read_text()),
    }
