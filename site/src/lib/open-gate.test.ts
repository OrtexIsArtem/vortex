import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from 'vitest';
import { OpenGate } from './open-gate';

describe('OpenGate', () => {
  let open: Mock<() => void>;
  let close: Mock<() => void>;
  let gate: OpenGate;

  beforeEach(() => {
    vi.useFakeTimers();
    open = vi.fn<() => void>();
    close = vi.fn<() => void>();
    gate = new OpenGate({
      openAt: 0.02,
      closeAt: 0.97,
      settle: 70,
      open,
      close,
      setTimer: (run, ms) => setTimeout(run, ms) as unknown as number,
      clearTimer: (id) => clearTimeout(id),
    });
  });

  afterEach(() => vi.useRealTimers());

  it('opens once the scroll has settled inside the scene', () => {
    gate.update(0.5);
    vi.advanceTimersByTime(69);
    expect(open).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(open).toHaveBeenCalledTimes(1);
  });

  it("doesn't open for a scroll that races through", () => {
    gate.update(0.5);
    gate.update(1.4);
    vi.advanceTimersByTime(200);
    expect(open).not.toHaveBeenCalled();
  });

  it('opens again when the scroll comes back after racing through', () => {
    gate.update(0.5);
    gate.update(1.4);
    vi.advanceTimersByTime(200);
    gate.update(0.5);
    vi.advanceTimersByTime(70);
    expect(open).toHaveBeenCalledTimes(1);
  });

  it('closes when the scroll leaves, and opens again on the way back', () => {
    gate.update(0.3);
    vi.advanceTimersByTime(70);
    gate.update(1.2);
    expect(close).toHaveBeenCalledTimes(1);
    gate.update(0.8);
    vi.advanceTimersByTime(70);
    gate.update(-0.5);
    gate.update(0.4);
    vi.advanceTimersByTime(70);
    expect(open).toHaveBeenCalledTimes(3);
    expect(close).toHaveBeenCalledTimes(2);
  });

  it('leaves a window the visitor closed shut until they scroll out and back', () => {
    gate.update(0.3);
    vi.advanceTimersByTime(70);
    gate.closedByVisitor();
    gate.update(0.6);
    vi.advanceTimersByTime(200);
    expect(open).toHaveBeenCalledTimes(1);
    gate.update(1.3);
    expect(close).not.toHaveBeenCalled();
    gate.update(0.6);
    vi.advanceTimersByTime(70);
    expect(open).toHaveBeenCalledTimes(2);
  });

  it('keeps holding the window while the scroll moves inside the scene', () => {
    gate.update(0.1);
    vi.advanceTimersByTime(70);
    for (const at of [0.2, 0.5, 0.9, 0.3]) gate.update(at);
    vi.advanceTimersByTime(500);
    expect(open).toHaveBeenCalledTimes(1);
    expect(close).not.toHaveBeenCalled();
    expect(gate.isHolding).toBe(true);
  });
});
