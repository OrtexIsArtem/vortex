import { describe, expect, it } from 'vitest';
import { articleGraph, landingGraph, serializeGraph } from './structured';

const home = 'https://vortex-notch.web.app/';
const tags = ['en', 'uk', 'de'];

const article = {
  home,
  landing: home,
  page: `${home}claude-code-secrets/`,
  title: 'Keep Secrets Away from Claude Code · Vortex',
  heading: 'Keep secrets away from Claude Code',
  description: 'How to keep secrets away from Claude Code.',
  label: 'Secrets and Claude Code',
  tag: 'en',
  tags,
  image: `${home}og.png`,
  published: new Date('2026-11-01'),
  modified: new Date('2026-11-03'),
  faq: [{ q: 'Does it work?', a: 'Yes, with `{{name}}` and [a link](https://example.com).' }],
};

type Node = Record<string, unknown>;
const byType = (graph: object[], type: string) => graph.find((node) => (node as Node)['@type'] === type) as Node | undefined;

describe('articleGraph', () => {
  it('describes the page as an article about the app, by its author, with its dates', () => {
    const node = byType(articleGraph(article), 'TechArticle');
    expect(node).toMatchObject({
      '@id': `${home}claude-code-secrets/#article`,
      headline: 'Keep secrets away from Claude Code',
      inLanguage: 'en',
      datePublished: '2026-11-01',
      dateModified: '2026-11-03',
      author: { '@type': 'Person', name: 'Artem Pronenko' },
      about: { '@id': `${home}#app` },
    });
  });

  it('leads back to the landing in the page’s language', () => {
    const node = byType(articleGraph({ ...article, landing: `${home}de/` }), 'BreadcrumbList');
    expect(node?.itemListElement).toEqual([
      { '@type': 'ListItem', position: 1, name: 'Vortex', item: `${home}de/` },
      { '@type': 'ListItem', position: 2, name: 'Secrets and Claude Code', item: `${home}claude-code-secrets/` },
    ]);
  });

  it('gives the questions as plain text, and none when the page shows none', () => {
    const faq = byType(articleGraph(article), 'FAQPage');
    expect(faq?.mainEntity).toEqual([
      { '@type': 'Question', name: 'Does it work?', acceptedAnswer: { '@type': 'Answer', text: 'Yes, with {{name}} and a link.' } },
    ]);
    expect(byType(articleGraph({ ...article, faq: [] }), 'FAQPage')).toBeUndefined();
  });

  it('shares the site’s node with the landing', () => {
    const landing = landingGraph({
      home,
      page: home,
      title: 't',
      description: 'd',
      tag: 'en',
      tags,
      image: `${home}og.png`,
      appVersion: '1.0',
      downloadUrl: 'https://example.com/v.zip',
      licenseUrl: 'https://example.com/LICENSE',
      repoUrl: 'https://example.com/repo',
    });
    expect(byType(articleGraph(article), 'WebSite')).toEqual(byType(landing, 'WebSite'));
  });
});

describe('serializeGraph', () => {
  it('keeps a < in the text from ending the script', () => {
    const text = serializeGraph([{ name: '</script><b>' }]);
    expect(text).not.toContain('<');
    expect(JSON.parse(text)).toEqual({ '@context': 'https://schema.org', '@graph': [{ name: '</script><b>' }] });
  });
});
