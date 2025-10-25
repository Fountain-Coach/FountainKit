#!/usr/bin/env python3
import argparse, os, sys

def ensure_imports(require_tf: bool):
    import importlib
    try:
        import coremltools as ct  # noqa: F401
    except Exception as e:
        print("[error] coremltools not available in venv: ", e, file=sys.stderr)
        sys.exit(1)
    if require_tf:
        try:
            import tensorflow as tf  # noqa: F401
        except Exception as e:
            print("[error] tensorflow not available in venv: ", e, file=sys.stderr)
            sys.exit(1)

def convert_generic(source, out_path: str, frame: int | None):
    import coremltools as ct
    inputs = None
    if frame is not None:
        # 1D audio frame [1, N]
        inputs = [ct.TensorType(name="input", shape=(1, frame), dtype=ct.models.datatypes.Array)
                  ]
    print(f"[convert] converting to {out_path} ...")
    mlmodel = ct.convert(source, inputs=inputs)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    mlmodel.save(out_path)
    print("[convert] wrote:", out_path)

def cmd_crepe(args):
    ensure_imports(require_tf=True)
    # For CREPE, we pass SavedModel directory directly; callers can control frame size
    convert_generic(args.saved_model, args.out, args.frame)

def cmd_basicpitch(args):
    ensure_imports(require_tf=True)
    convert_generic(args.saved_model, args.out, None)

def cmd_keras(args):
    ensure_imports(require_tf=True)
    import tensorflow as tf
    model = tf.keras.models.load_model(args.h5, compile=False)
    convert_generic(model, args.out, args.frame)

def cmd_tflite(args):
    ensure_imports(require_tf=False)
    convert_generic(args.tflite, args.out, args.frame)

def main():
    p = argparse.ArgumentParser(description="Core ML conversion helper")
    sp = p.add_subparsers(dest="cmd", required=True)

    crepe = sp.add_parser("crepe", help="Convert CREPE SavedModel to .mlmodel")
    crepe.add_argument("--saved-model", required=True)
    crepe.add_argument("--frame", type=int, default=1024)
    crepe.add_argument("--out", required=True)
    crepe.set_defaults(fn=cmd_crepe)

    bp = sp.add_parser("basicpitch", help="Convert BasicPitch SavedModel to .mlmodel")
    bp.add_argument("--saved-model", required=True)
    bp.add_argument("--out", required=True)
    bp.set_defaults(fn=cmd_basicpitch)

    k = sp.add_parser("keras", help="Convert Keras .h5 to .mlmodel")
    k.add_argument("--h5", required=True)
    k.add_argument("--frame", type=int, default=1024)
    k.add_argument("--out", required=True)
    k.set_defaults(fn=cmd_keras)

    t = sp.add_parser("tflite", help="Convert TFLite .tflite to .mlmodel")
    t.add_argument("--tflite", required=True)
    t.add_argument("--frame", type=int, default=1024)
    t.add_argument("--out", required=True)
    t.set_defaults(fn=cmd_tflite)

    args = p.parse_args()
    args.fn(args)

if __name__ == "__main__":
    main()

