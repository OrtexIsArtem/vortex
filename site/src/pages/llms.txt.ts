// What the product is, for AI search and assistants (llmstxt.org): written from the English page's own words, so it
// never drifts from the site, each part linking to its place on the page; then the English guides, by their own words.
import type { APIRoute } from 'astro';
import { en } from '../copy/en';
import { defaultLocale, locales, pathFor } from '../copy/locales';
import { appVersion, buildUrl, contributingUrl, downloadUrl, licenseUrl, releasesUrl, repoUrl } from '../lib/app';
import { guidesFor } from '../lib/content';
import { inlineText } from '../lib/inline';

export const GET: APIRoute = async ({ site }) => {
  const guides = await guidesFor(defaultLocale);
  const url = (path: string) => (site ? new URL(path, site).href : path);
  // A part of the English page.
  const at = (id: string) => url(`${pathFor(defaultLocale)}#${id}`);
  const chapters = [
    { id: 'timer', chapter: en.timerChapter },
    { id: 'clipboard', chapter: en.clipboardChapter },
    { id: 'shelf', chapter: en.shelfChapter },
    { id: 'tasks', chapter: en.tasksChapter },
    { id: 'keys', chapter: en.keysChapter },
    { id: 'keyboard', chapter: en.keyboardChapter },
  ];
  const text = [
    '# Vortex',
    '',
    `> ${en.meta.description}`,
    '',
    `${en.hero.tagline} ${en.hero.lead}`,
    '',
    `Version ${appVersion}. macOS 14 or later, on Apple silicon (M1 and later). Free and open source under the MIT license. Intel Macs aren't supported.`,
    '',
    '## Features',
    '',
    ...chapters.map(({ id, chapter }) => `- [${chapter.label}](${at(id)}): ${chapter.title} ${chapter.body} (${chapter.facts.join('; ')}.)`),
    ...en.more.items.map((item) => `- [${item.title.replace(/\.$/, '')}](${at('more')}): ${inlineText(item.text)}`),
    '',
    '## Privacy',
    '',
    `- [${en.privacy.title} ${en.privacy.titleQuiet}](${at('privacy')}): ${en.privacy.body}`,
    ...en.privacy.facts.map((fact) => `- ${fact.label}: ${inlineText(fact.text)}`),
    '',
    '## Install',
    '',
    `- [Download](${downloadUrl}): ${en.download.meta(appVersion)}`,
    ...en.download.steps.map((step, index) => `- First launch, step ${index + 1}: ${step}`),
    `- ${en.download.terminal} \`${en.download.install}\``,
    `- [Build it yourself](${buildUrl}): ${en.openSource.commands.map((command) => `\`${command}\``).join(', ')}. You need Xcode.`,
    '',
    '## Questions',
    '',
    ...en.faq.items(contributingUrl).map((item) => `- [${item.q}](${at('faq')}): ${inlineText(item.a)}`),
    '',
    ...(guides.length > 0 ? ['## Guides', '', ...guides.map((guide) => `- [${guide.heading}](${url(guide.href)}): ${guide.description}`), ''] : []),
    '## Links',
    '',
    `- [Website](${url(pathFor(defaultLocale))}): English`,
    `- [Source code](${repoUrl})`,
    `- [Releases](${releasesUrl})`,
    `- [How to contribute](${contributingUrl})`,
    `- [License: MIT](${licenseUrl})`,
    '',
    '## Optional',
    '',
    ...locales.filter((locale) => locale.code !== defaultLocale).map((locale) => `- [${locale.name}](${url(pathFor(locale.code))})`),
    '',
  ].join('\n');
  return new Response(text, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
