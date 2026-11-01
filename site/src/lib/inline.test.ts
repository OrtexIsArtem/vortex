import { describe, expect, it } from 'vitest';
import { inlineHtml, inlineText } from './inline';

describe('inlineHtml', () => {
  it('escapes plain text', () => {
    expect(inlineHtml('Tom & <Jerry> "said" it\'s')).toBe('Tom &amp; &lt;Jerry&gt; &quot;said&quot; it&#39;s');
  });

  it('puts code in <code>, escaped', () => {
    expect(inlineHtml('Run `open -a Vortex <files>` now')).toBe('Run <code>open -a Vortex &lt;files&gt;</code> now');
  });

  it('turns a link into <a>', () => {
    expect(inlineHtml('See [CONTRIBUTING.md](https://example.com/a?b=1&c=2).')).toBe(
      'See <a href="https://example.com/a?b=1&amp;c=2">CONTRIBUTING.md</a>.',
    );
  });

  it('handles several marks in a row', () => {
    expect(inlineHtml('`a` and [b](#c) and `{{name}}`')).toBe('<code>a</code> and <a href="#c">b</a> and <code>{{name}}</code>');
  });
});

describe('inlineText', () => {
  it('drops the marks and keeps a link label', () => {
    expect(inlineText('Copy `Features/_Template`; [CONTRIBUTING.md](https://x.y) walks you through it.')).toBe(
      'Copy Features/_Template; CONTRIBUTING.md walks you through it.',
    );
  });

  it('leaves text without marks alone', () => {
    expect(inlineText('Yes. Free and open source.')).toBe('Yes. Free and open source.');
  });
});
