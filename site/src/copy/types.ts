// The shape every language's copy has: the English one, its words widened to any string. Icon names and kinds stay
// exact, since components draw by them.
import type { en } from './en';

type Widen<T> = T extends string
  ? string
  : T extends (...args: infer A) => infer R
    ? (...args: A) => Widen<R>
    : T extends readonly (infer U)[]
      ? readonly Widen<U>[]
      : T extends object
        ? { readonly [K in keyof T]: K extends 'icon' | 'kind' ? T[K] : Widen<T[K]> }
        : T;

export type Copy = Widen<typeof en>;
