"""
Train SwimTCN on synthetic or real+synthetic data.

Usage:
    python -m ml.train                              # from swim-analyzer/ directory
    python -m ml.train --epochs 30 --n 8000
    python -m ml.train --data /tmp/swim_dataset.npz --epochs 40

Saves weights to ml/swim_tcn.pt
"""

import argparse
import os
import time

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from .model import SwimTCN, ISSUE_LABELS
from .datagen import generate_dataset


def train(
    n_samples: int = 8000,
    seq_len: int = 90,
    epochs: int = 30,
    batch_size: int = 64,
    lr: float = 1e-3,
    val_split: float = 0.15,
    seed: int = 42,
    weights_path: str = None,
    data_path: str = None,
) -> SwimTCN:
    if weights_path is None:
        weights_path = os.path.join(os.path.dirname(__file__), "swim_tcn.pt")

    torch.manual_seed(seed)
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"Device: {device}")

    if data_path is not None:
        print(f"Loading dataset from {data_path} ...")
        t0 = time.time()
        npz = np.load(data_path)
        X, y = npz["X"], npz["y"]
        n_samples = len(X)
        print(f"  Loaded {n_samples} samples in {time.time()-t0:.1f}s. Label distribution:")
        for i, name in enumerate(ISSUE_LABELS):
            print(f"    {name}: {y[:, i].sum():.0f} positive ({y[:, i].mean()*100:.1f}%)")
    else:
        print(f"Generating {n_samples} synthetic samples (seq_len={seq_len})...")
        t0 = time.time()
        X, y = generate_dataset(n_samples=n_samples, seq_len=seq_len, seed=seed)
        print(f"  Done in {time.time()-t0:.1f}s. Label distribution:")
        for i, name in enumerate(ISSUE_LABELS):
            print(f"    {name}: {y[:, i].sum():.0f} positive ({y[:, i].mean()*100:.1f}%)")

    # Train / val split
    n_val = int(n_samples * val_split)
    n_train = n_samples - n_val
    X_tr, y_tr = torch.tensor(X[:n_train]), torch.tensor(y[:n_train])
    X_val, y_val = torch.tensor(X[n_train:]), torch.tensor(y[n_train:])

    train_dl = DataLoader(TensorDataset(X_tr, y_tr), batch_size=batch_size, shuffle=True)
    val_dl   = DataLoader(TensorDataset(X_val, y_val), batch_size=batch_size)

    model = SwimTCN().to(device)

    # weight_decay=1e-3 prevents weight explosion / logit saturation
    opt   = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-3)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)

    # Compute pos_weight from training label frequencies.
    # pos_weight[i] = (n_neg_i / n_pos_i); if label is balanced, pos_weight ≈ 1.
    label_pos = y_tr.sum(dim=0).clamp(min=1.0)
    label_neg = (n_train - label_pos).clamp(min=1.0)
    pos_weight = (label_neg / label_pos).to(device)
    print(f"  pos_weight (per label): {pos_weight.cpu().numpy().round(2)}")

    # BCEWithLogitsLoss expects raw logits (no sigmoid in model.forward).
    # Label smoothing (epsilon=0.1) prevents the model from pushing logits to
    # ±infinity on perfectly separable labels, which causes saturation.
    label_smoothing = 0.1

    def loss_fn(logits, targets):
        # Smooth targets: 0 → 0.1/2 = 0.05, 1 → 1 - 0.1/2 = 0.95
        smoothed = targets * (1 - label_smoothing) + 0.5 * label_smoothing
        return nn.functional.binary_cross_entropy_with_logits(
            logits, smoothed, pos_weight=pos_weight
        )

    best_val = float("inf")
    for epoch in range(1, epochs + 1):
        model.train()
        tr_loss = 0.0
        for xb, yb in train_dl:
            xb, yb = xb.to(device), yb.to(device)
            logits = model(xb)
            loss = loss_fn(logits, yb)
            opt.zero_grad()
            loss.backward()
            opt.step()
            tr_loss += loss.item() * len(xb)
        tr_loss /= n_train

        model.eval()
        val_loss = 0.0
        correct = total = 0
        all_preds = []
        all_targets = []
        with torch.no_grad():
            for xb, yb in val_dl:
                xb, yb = xb.to(device), yb.to(device)
                logits = model(xb)
                val_loss += loss_fn(logits, yb).item() * len(xb)
                probs = torch.sigmoid(logits)
                preds = (probs > 0.5)
                correct += (preds == yb.bool()).all(dim=1).sum().item()
                total += len(xb)
                all_preds.append(preds.cpu())
                all_targets.append(yb.bool().cpu())
        val_loss /= n_val
        acc = correct / total

        sched.step()

        if val_loss < best_val:
            best_val = val_loss
            torch.save(model.state_dict(), weights_path)
            marker = " ✓"
        else:
            marker = ""

        if epoch % 5 == 0 or epoch == 1:
            print(f"  Epoch {epoch:3d}/{epochs} | tr={tr_loss:.4f} val={val_loss:.4f} "
                  f"exact_acc={acc:.3f}{marker}")

    print(f"\nBest val loss: {best_val:.4f}")
    print(f"Saved to: {weights_path}")

    # Load best weights
    model.load_state_dict(torch.load(weights_path, map_location=device))
    model.eval()

    # ----- Per-label precision / recall on validation set -----
    all_preds_t = torch.cat(all_preds, dim=0).float()   # (n_val, 10)
    all_targets_t = torch.cat(all_targets, dim=0).float()

    print("\nPer-label val metrics (threshold=0.5):")
    print(f"  {'Label':<30} {'Prec':>6} {'Rec':>6} {'F1':>6} {'Pos%':>6}")
    for i, name in enumerate(ISSUE_LABELS):
        tp = (all_preds_t[:, i] * all_targets_t[:, i]).sum().item()
        fp = (all_preds_t[:, i] * (1 - all_targets_t[:, i])).sum().item()
        fn = ((1 - all_preds_t[:, i]) * all_targets_t[:, i]).sum().item()
        prec = tp / (tp + fp + 1e-9)
        rec  = tp / (tp + fn + 1e-9)
        f1   = 2 * prec * rec / (prec + rec + 1e-9)
        pos_pct = all_targets_t[:, i].mean().item() * 100
        print(f"  {name:<30} {prec:6.3f} {rec:6.3f} {f1:6.3f} {pos_pct:5.1f}%")

    # ----- Sanity check: inference on zeros and random noise -----
    print("\nSanity check — model outputs (after sigmoid):")
    model_cpu = model.to("cpu")
    with torch.no_grad():
        zeros_input  = torch.zeros(1, 39, 90)
        noise_input  = torch.randn(1, 39, 90)
        zeros_logits = model_cpu(zeros_input)
        noise_logits = model_cpu(noise_input)
        zeros_probs  = torch.sigmoid(zeros_logits).squeeze().numpy()
        noise_probs  = torch.sigmoid(noise_logits).squeeze().numpy()

    print(f"  Zeros input  min={zeros_probs.min():.4f} max={zeros_probs.max():.4f}")
    print(f"  Noise input  min={noise_probs.min():.4f} max={noise_probs.max():.4f}")

    ok_zeros = (zeros_probs > 0.13).all() and (zeros_probs < 0.87).all()
    ok_noise = (noise_probs > 0.13).all() and (noise_probs < 0.87).all()
    print(f"  Zeros in (0.13, 0.87): {ok_zeros}")
    print(f"  Noise in (0.13, 0.87): {ok_noise}")
    if ok_zeros and ok_noise:
        print("  PASS: model is NOT saturated.")
    else:
        print("  WARNING: some outputs are saturated.")

    # ----- Sanity checks 3 & 4: injected anomaly sequences -----
    from .datagen import (
        _make_swimmer_base,
        _inject_body_sag,
        _inject_stroke_asymmetry,
        N_JOINTS as _N_JOINTS,
    )

    _fps = 30.0
    _t   = np.arange(90) / _fps

    # Check 3: clear body_sag (label index 6)
    kp_sag = _make_swimmer_base(_t, noise=0.001)
    kp_sag = _inject_body_sag(kp_sag)
    x_sag  = torch.tensor(kp_sag.transpose(1, 2, 0).reshape(_N_JOINTS * 3, 90)[None])
    with torch.no_grad():
        sag_prob = torch.sigmoid(model_cpu(x_sag)).squeeze().numpy()
    body_sag_prob = float(sag_prob[ISSUE_LABELS.index("body_sag")])
    ok_sag = body_sag_prob > 0.65
    print(f"\n  Body-sag injection  → body_sag prob = {body_sag_prob:.4f}  "
          f"({'PASS' if ok_sag else 'WARN'} >0.65)")

    # Check 4: clear stroke_asymmetry (label index 7)
    kp_asym = _make_swimmer_base(_t, noise=0.001)
    kp_asym = _inject_stroke_asymmetry(kp_asym)
    x_asym  = torch.tensor(kp_asym.transpose(1, 2, 0).reshape(_N_JOINTS * 3, 90)[None])
    with torch.no_grad():
        asym_prob = torch.sigmoid(model_cpu(x_asym)).squeeze().numpy()
    stroke_asym_prob = float(asym_prob[ISSUE_LABELS.index("stroke_asymmetry")])
    ok_asym = stroke_asym_prob > 0.65
    print(f"  Stroke-asym injection → stroke_asymmetry prob = {stroke_asym_prob:.4f}  "
          f"({'PASS' if ok_asym else 'WARN'} >0.65)")

    # Check 5: real-like sequences (no body_sag injection) should NOT
    # always predict body_sag at the saturated-high value (0.87).
    # Pass conditions:
    #   (a) all clean-pose predictions < 0.87  (not stuck high)
    #   (b) injected-sag prob is clearly higher than clean mean (gap > 0.2)
    # This catches both "always 0.87" saturation AND "no discrimination" failure.
    rng_check = np.random.default_rng(999)
    sag_probs_real_like = []
    for _ in range(20):
        kp_rl = _make_swimmer_base(_t, noise=rng_check.random() * 0.01)
        x_rl  = torch.tensor(kp_rl.transpose(1, 2, 0).reshape(_N_JOINTS * 3, 90)[None])
        with torch.no_grad():
            rl_prob = torch.sigmoid(model_cpu(x_rl)).squeeze().numpy()
        sag_probs_real_like.append(float(rl_prob[ISSUE_LABELS.index("body_sag")]))
    sag_probs_arr = np.array(sag_probs_real_like)
    gap = body_sag_prob - sag_probs_arr.mean()
    ok_real_like = (sag_probs_arr < 0.87).all() and gap > 0.2
    print(f"\n  Real-like seqs body_sag probs: min={sag_probs_arr.min():.4f} "
          f"max={sag_probs_arr.max():.4f} mean={sag_probs_arr.mean():.4f}  "
          f"sag-gap={gap:.4f}  "
          f"({'PASS' if ok_real_like else 'WARN'} — should not always be 0.87)")

    all_sanity_pass = ok_zeros and ok_noise and ok_sag and ok_asym and ok_real_like
    print(f"\n  Overall sanity: {'ALL PASS' if all_sanity_pass else 'SOME CHECKS FAILED'}")

    return model


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", type=int, default=8000, help="Number of training samples (ignored if --data is set)")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--seq_len", type=int, default=90)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--data", type=str, default=None,
                        help="Path to .npz dataset (X, y arrays). If provided, skips datagen.")
    args = parser.parse_args()
    train(n_samples=args.n, seq_len=args.seq_len, epochs=args.epochs, lr=args.lr,
          data_path=args.data)
