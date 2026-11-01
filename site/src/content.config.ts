// The site's long-form pages, in Markdown: src/content/pages/<language>/<slug>.md. The folder is the page's language
// and the file name its address, the same in every language (/claude-code-secrets/, /de/claude-code-secrets/). A page
// exists in English first; a translation is the same file name under another language's folder.
import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

const pages = defineCollection({
  loader: glob({
    pattern: '**/*.md',
    base: './src/content/pages',
    // The path, never a `slug` in the frontmatter: a page's translations share its slug, so it can't be the id.
    generateId: ({ entry }) => entry.replace(/\.md$/, ''),
  }),
  schema: z.strictObject({
    /** The page's <title> as search results show it, the site's name included: 60 characters at most. */
    title: z.string().min(1).max(60),
    /** The search result's snippet and the social preview's text: 160 characters at most. */
    description: z.string().min(50).max(160),
    /** The page's one H1, and the landing's link to it. The body starts at ## (H2). */
    heading: z.string().min(1).max(90),
    /** A short name for the page in the breadcrumb, the footer's Guides and the landing's link to it. */
    label: z.string().min(1).max(40),
    published: z.coerce.date(),
    /** When the page last changed in substance; search engines and the page itself show it. */
    updated: z.coerce.date(),
    /** The landing chapter the page belongs to: that chapter links to it at its end. */
    chapter: z.enum(['timer', 'clipboard', 'shelf', 'tasks', 'keys', 'keyboard']).optional(),
    /** The page's own questions, shown under its text and given to search engines as FAQPage. Answers take `code` and
     * [links](https://…), as the landing's do. */
    faq: z
      .array(z.strictObject({ q: z.string().min(1), a: z.string().min(1) }))
      .max(8)
      .default([]),
  }),
});

export const collections = { pages };
