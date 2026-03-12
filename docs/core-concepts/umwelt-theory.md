# The Umwelt Concept

## Origin

In 1909, Estonian-German biologist **Jakob von Uexküll** introduced the concept of *Umwelt* (German: "surrounding world") in his work on theoretical biology. The core insight: every organism inhabits its own subjective perceptual world, constructed from the signals its sensory apparatus can detect.

A tick perceives only three things: butyric acid (mammal skin), warmth (blood temperature), and hair density (where to bite). That is the tick's entire Umwelt — its self-centered perceptual bubble. The rest of the universe does not exist for it.

## Applied to AI

An AI coding assistant faces the same constraint. It sits inside a context window with no sensors. It cannot perceive:

- Your git branch or recent changes
- Whether tests are passing or failing
- What services are running
- Whether dependencies have vulnerabilities
- What your project structure looks like

Without environmental perception, it operates blind — guessing about context you take for granted.

## What Umwelt Does

Umwelt constructs the AI's perceptual world by:

1. **Sensing** — 7 specialized loaders scan different dimensions of your environment
2. **Filtering** — Intelligent loaders skip irrelevant data (no Docker output if Docker isn't running)
3. **Predicting** — Message analysis predicts which sensors matter before scanning
4. **Diffing** — Only changed perceptions are injected, saving 80-90% of tokens
5. **Assembling** — Structured output ordered for Claude's internal prompt architecture

The result: a complete, efficient, contextually relevant picture of your development environment — the AI's Umwelt.

## The Sigil Connection

Umwelt comes from biosemiotics — the study of how organisms create and interpret signs in their environment. [Sigil](https://github.com/pkmdev-sec/sigil) comes from semiotics — the study of signs and meaning.

Together they form the complete Claude Code intelligence stack:
- **Sigil** crafts the intent (how the AI should behave)
- **Umwelt** constructs the perception (what the AI can see)
