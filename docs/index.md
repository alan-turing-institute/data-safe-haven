# Safe Haven Documentation

We organise our documentation into four types. Read in accordance to what might be most helpful to you.

## Tutorials and overview

**Recommended if**: you have no prior experience using our Safe Havens and want to be guided through the basics. Instructions about how to deploy your own Safe Haven are here.

See [Tutorials and overview](tutorial/README.md) for more information

## How-to guides

**Recommended if**: You want to use a Safe Haven that you, or someone else, has already deployed (following the instructions in the tutorial).

See [How-to guides](how_to_guides/README.md) for more information

## Explanations and design decisions

**Recommended if**: You want to develop a deeper understanding of the different aspects of Safe Haven design and the motivations behind them.

See [Explanations](explanations/README.md)

## Reference materials

**Recommended if**: You want a technical understanding of aspects of our Safe Haven implementation using Azure.

See [Reference](reference/README.md)

## Converting documentation to PDF

There are several ways to make shareable PDF files from the documents above.
The easiest way to make shareable PDF files from the Markdown documents included here is using the `markdown2pdf.sh` script.

+ `npm` method [recommended]
  + Install `npm`
  + Install `pretty-markdown-pdf` with `npm install pretty-markdown-pdf` with the -g flag if you want it installed globally
  + Run `./markdown2pdf.sh <file name>.md npm`
+ `LaTeX` method
  + Install [`XeLaTex`](http://xetex.sourceforge.net/), generally by installing a full LaTeX environment such as [`TexLive`](http://www.tug.org/texlive/) (Windows / Linux) or [`MacTex`](http://www.tug.org/mactex/) (macOS).
  + Install [`Pandoc`](https://pandoc.org/installing.html)`
  + Install the `Symbola` font (https://dn-works.com/ufas/)
  + Run `./markdown2pdf.sh <file name>.md latex`


:::{note}
This text is **standard** _Markdown_
:::

:::{important}
This text is also **standard** _Markdown_
:::

:::{table} This is a **standard** _Markdown_ title
:align: center
:widths: grid

abc | mnp | xyz
--- | --- | ---
123 | 456 | 789
:::

<div class="admonition note" name="html-admonition" style="background: lightgreen; padding: 10px">
<p class="title">This is the **title**</p>
This is the *content*
</div>