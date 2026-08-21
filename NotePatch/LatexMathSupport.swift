import WebKit

enum LatexMathSupport {
    static func install(into configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: renderingScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
    }

    nonisolated static let renderCommand = "globalThis.__notePatchRenderMath && globalThis.__notePatchRenderMath(document.body);"

    nonisolated static let renderingScript = #"""
    (() => {
      'use strict';

      const scope = typeof globalThis !== 'undefined' ? globalThis : window;
      if (scope.__notePatchRenderMath) {
        if (typeof document !== 'undefined') scope.__notePatchRenderMath(document.body);
        return;
      }

      const escapeHTML = value => String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');

      const tag = (name, content, attributes = '') =>
        `<${name}${attributes ? ` ${attributes}` : ''}>${content}</${name}>`;
      const row = parts => parts.length === 1 ? parts[0] : tag('mrow', parts.join(''));

      const symbols = {
        alpha: '&#x03B1;', beta: '&#x03B2;', gamma: '&#x03B3;', delta: '&#x03B4;',
        epsilon: '&#x03F5;', varepsilon: '&#x03B5;', zeta: '&#x03B6;', eta: '&#x03B7;',
        theta: '&#x03B8;', vartheta: '&#x03D1;', iota: '&#x03B9;', kappa: '&#x03BA;',
        lambda: '&#x03BB;', mu: '&#x03BC;', nu: '&#x03BD;', xi: '&#x03BE;',
        pi: '&#x03C0;', varpi: '&#x03D6;', rho: '&#x03C1;', sigma: '&#x03C3;',
        tau: '&#x03C4;', upsilon: '&#x03C5;', phi: '&#x03C6;', varphi: '&#x03D5;',
        chi: '&#x03C7;', psi: '&#x03C8;', omega: '&#x03C9;',
        Gamma: '&#x0393;', Delta: '&#x0394;', Theta: '&#x0398;', Lambda: '&#x039B;',
        Xi: '&#x039E;', Pi: '&#x03A0;', Sigma: '&#x03A3;', Upsilon: '&#x03A5;',
        Phi: '&#x03A6;', Psi: '&#x03A8;', Omega: '&#x03A9;',
        infty: '&#x221E;', partial: '&#x2202;', nabla: '&#x2207;', ell: '&#x2113;',
        hbar: '&#x210F;', imath: '&#x0131;', jmath: '&#x0237;'
      };

      const operators = {
        times: '&#x00D7;', div: '&#x00F7;', cdot: '&#x22C5;', ast: '&#x2217;',
        star: '&#x22C6;', circ: '&#x2218;', bullet: '&#x2219;', pm: '&#x00B1;',
        mp: '&#x2213;', cap: '&#x2229;', cup: '&#x222A;', setminus: '&#x2216;',
        land: '&#x2227;', lor: '&#x2228;', oplus: '&#x2295;', otimes: '&#x2297;',
        le: '&#x2264;', leq: '&#x2264;', ge: '&#x2265;', geq: '&#x2265;',
        ne: '&#x2260;', neq: '&#x2260;', approx: '&#x2248;', sim: '&#x223C;',
        simeq: '&#x2243;', equiv: '&#x2261;', propto: '&#x221D;',
        in: '&#x2208;', notin: '&#x2209;', ni: '&#x220B;', subset: '&#x2282;',
        supset: '&#x2283;', subseteq: '&#x2286;', supseteq: '&#x2287;',
        to: '&#x2192;', rightarrow: '&#x2192;', leftarrow: '&#x2190;',
        leftrightarrow: '&#x2194;', Rightarrow: '&#x21D2;', Leftarrow: '&#x21D0;',
        Leftrightarrow: '&#x21D4;', mapsto: '&#x21A6;', implies: '&#x21D2;',
        iff: '&#x21D4;', perpendicular: '&#x27C2;', parallel: '&#x2225;',
        angle: '&#x2220;', degree: '&#x00B0;', ldots: '&#x2026;', cdots: '&#x22EF;',
        vdots: '&#x22EE;', ddots: '&#x22F1;', therefore: '&#x2234;', because: '&#x2235;'
      };

      const largeOperators = {
        sum: '&#x2211;', prod: '&#x220F;', coprod: '&#x2210;', int: '&#x222B;',
        iint: '&#x222C;', iiint: '&#x222D;', oint: '&#x222E;', bigcup: '&#x22C3;',
        bigcap: '&#x22C2;', bigoplus: '&#x2A01;', bigotimes: '&#x2A02;'
      };

      const unicodeOperators = {
        '×': '&#x00D7;', '÷': '&#x00F7;', '±': '&#x00B1;', '∓': '&#x2213;',
        '≤': '&#x2264;', '≥': '&#x2265;', '≠': '&#x2260;', '≈': '&#x2248;',
        '∝': '&#x221D;', '∈': '&#x2208;', '∉': '&#x2209;', '∩': '&#x2229;',
        '∪': '&#x222A;', '→': '&#x2192;', '←': '&#x2190;', '↔': '&#x2194;'
      };

      const functions = new Set([
        'sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'arcsin', 'arccos', 'arctan',
        'sinh', 'cosh', 'tanh', 'log', 'ln', 'lg', 'exp', 'lim', 'min', 'max',
        'inf', 'sup', 'gcd', 'det', 'dim', 'ker', 'Pr'
      ]);

      class TeXParser {
        constructor(source, display) {
          this.source = source || '';
          this.index = 0;
          this.display = !!display;
        }

        parse(stopCharacter = null) {
          const parts = [];
          while (this.index < this.source.length) {
            const character = this.source[this.index];
            if (stopCharacter && character === stopCharacter) {
              this.index += 1;
              break;
            }
            if (/\s/.test(character)) {
              this.index += 1;
              continue;
            }
            let atom = this.parseAtom();
            if (!atom) continue;
            atom = this.parseScripts(atom);
            parts.push(atom);
          }
          return row(parts);
        }

        parseAtom() {
          const character = this.source[this.index];
          if (!character) return '';
          if (character === '{') {
            this.index += 1;
            return tag('mrow', this.parse('}'));
          }
          if (character === '}') {
            this.index += 1;
            return '';
          }
          if (character === '\\') return this.parseCommand();
          if (character === '√') {
            this.index += 1;
            this.skipSpaces();
            if (this.source[this.index] === '(') {
              this.index += 1;
              return tag('msqrt', tag('mrow', this.parse(')')));
            }
            return tag('msqrt', tag('mrow', this.parseRequiredGroup()));
          }
          if (/[0-9]/.test(character)) {
            const start = this.index;
            while (this.index < this.source.length && /[0-9.,]/.test(this.source[this.index])) this.index += 1;
            return tag('mn', escapeHTML(this.source.slice(start, this.index)));
          }
          if (/[A-Za-z]/.test(character)) {
            const start = this.index;
            while (this.index < this.source.length && /[A-Za-z]/.test(this.source[this.index])) this.index += 1;
            const word = this.source.slice(start, this.index);
            if (word === 'pi') return tag('mi', '&#x03C0;');
            if (functions.has(word)) return tag('mi', escapeHTML(word), 'mathvariant="normal"');
            if (word.length === 1) return tag('mi', escapeHTML(word));
            return tag('mtext', `${escapeHTML(word)}&#xA0;`);
          }
          this.index += 1;
          if (unicodeOperators[character]) return tag('mo', unicodeOperators[character]);
          if (character === 'π') return tag('mi', '&#x03C0;');
          if ('+-=*/<>|:;,()[]'.includes(character)) return tag('mo', escapeHTML(character));
          return tag('mtext', escapeHTML(character));
        }

        parseCommand() {
          this.index += 1;
          if (this.index >= this.source.length) return tag('mo', '\\');
          const start = this.index;
          if (/[A-Za-z]/.test(this.source[this.index])) {
            while (this.index < this.source.length && /[A-Za-z]/.test(this.source[this.index])) this.index += 1;
          } else {
            this.index += 1;
          }
          const command = this.source.slice(start, this.index);

          if (['displaystyle', 'textstyle', 'scriptstyle', 'scriptscriptstyle'].includes(command)) return '';
          if (['frac', 'dfrac', 'tfrac', 'binom'].includes(command)) {
            const numerator = this.parseRequiredGroup();
            const denominator = this.parseRequiredGroup();
            const fraction = tag('mfrac', tag('mrow', numerator) + tag('mrow', denominator), command === 'tfrac' ? 'displaystyle="false"' : '');
            return command === 'binom' ? tag('mrow', tag('mo', '(') + fraction + tag('mo', ')')) : fraction;
          }
          if (command === 'sqrt') {
            const degree = this.parseOptionalGroup();
            this.skipSpaces();
            let radicand;
            if (this.source[this.index] === '(') {
              this.index += 1;
              radicand = this.parse(')');
            } else {
              radicand = this.parseRequiredGroup();
            }
            return degree === null
              ? tag('msqrt', tag('mrow', radicand))
              : tag('mroot', tag('mrow', radicand) + tag('mrow', new TeXParser(degree, this.display).parse()));
          }
          if (['text', 'textrm', 'textnormal'].includes(command)) {
            return tag('mtext', escapeHTML(this.readRawGroup()));
          }
          if (['mathrm', 'mathbf', 'mathit', 'mathsf', 'mathtt'].includes(command)) {
            const variants = {mathrm: 'normal', mathbf: 'bold', mathit: 'italic', mathsf: 'sans-serif', mathtt: 'monospace'};
            return tag('mstyle', this.parseRequiredGroup(), `mathvariant="${variants[command]}"`);
          }
          if (command === 'operatorname') {
            return tag('mi', escapeHTML(this.readRawGroup()), 'mathvariant="normal"');
          }
          if (['hat', 'widehat', 'bar', 'overline', 'vec', 'dot', 'ddot'].includes(command)) {
            const accents = {hat: '^', widehat: '^', bar: '&#x00AF;', overline: '&#x00AF;', vec: '&#x2192;', dot: '&#x02D9;', ddot: '&#x00A8;'};
            return tag('mover', this.parseRequiredGroup() + tag('mo', accents[command]), 'accent="true"');
          }
          if (command === 'underline') {
            return tag('munder', this.parseRequiredGroup() + tag('mo', '_'), 'accentunder="true"');
          }
          if (command === 'overbrace' || command === 'underbrace') {
            const content = this.parseRequiredGroup();
            const brace = tag('mo', command === 'overbrace' ? '&#x23DE;' : '&#x23DF;');
            return command === 'overbrace' ? tag('mover', content + brace) : tag('munder', content + brace);
          }
          if (command === 'boxed') return tag('menclose', this.parseRequiredGroup(), 'notation="box"');
          if (command === 'cancel') return tag('menclose', this.parseRequiredGroup(), 'notation="updiagonalstrike"');
          if (command === 'left' || command === 'right') return this.parseDelimiter();
          if (symbols[command]) return tag('mi', symbols[command]);
          if (operators[command]) return tag('mo', operators[command]);
          if (largeOperators[command]) return tag('mo', largeOperators[command], 'largeop="true" movablelimits="true"');
          if (functions.has(command)) return tag('mi', escapeHTML(command), 'mathvariant="normal"');
          if ([',', ';', ':', ' ', 'quad', 'qquad', 'enspace', 'thinspace'].includes(command)) {
            const widths = {',': '.167em', ';': '.278em', ':': '.222em', ' ': '.333em', quad: '1em', qquad: '2em', enspace: '.5em', thinspace: '.167em'};
            return `<mspace width="${widths[command]}"/>`;
          }
          if (command === '!') return '<mspace width="-.167em"/>';
          if (command === '\\') return '<mspace linebreak="newline"/>';
          if (['{', '}', '_', '%', '#', '&', '$'].includes(command)) return tag('mo', escapeHTML(command));
          return tag('mi', escapeHTML(command), 'mathvariant="normal"');
        }

        parseScripts(base) {
          let subscript = null;
          let superscript = null;
          while (this.index < this.source.length) {
            this.skipSpaces();
            const marker = this.source[this.index];
            if (marker !== '_' && marker !== '^') break;
            this.index += 1;
            const value = this.parseRequiredGroup();
            if (marker === '_') subscript = value;
            else superscript = value;
          }
          const useLimits = this.display && base.includes('largeop="true"');
          if (subscript !== null && superscript !== null) {
            return tag(useLimits ? 'munderover' : 'msubsup', base + tag('mrow', subscript) + tag('mrow', superscript));
          }
          if (subscript !== null) return tag(useLimits ? 'munder' : 'msub', base + tag('mrow', subscript));
          if (superscript !== null) return tag(useLimits ? 'mover' : 'msup', base + tag('mrow', superscript));
          return base;
        }

        parseRequiredGroup() {
          this.skipSpaces();
          if (this.source[this.index] === '{') {
            this.index += 1;
            return this.parse('}');
          }
          const atom = this.parseAtom();
          return atom ? this.parseScripts(atom) : tag('mrow', '');
        }

        parseOptionalGroup() {
          this.skipSpaces();
          if (this.source[this.index] !== '[') return null;
          this.index += 1;
          const start = this.index;
          let depth = 0;
          while (this.index < this.source.length) {
            const character = this.source[this.index];
            if (character === '{') depth += 1;
            if (character === '}') depth = Math.max(0, depth - 1);
            if (character === ']' && depth === 0) {
              const value = this.source.slice(start, this.index);
              this.index += 1;
              return value;
            }
            this.index += 1;
          }
          return this.source.slice(start);
        }

        readRawGroup() {
          this.skipSpaces();
          if (this.source[this.index] !== '{') return '';
          this.index += 1;
          const start = this.index;
          let depth = 1;
          while (this.index < this.source.length && depth > 0) {
            const character = this.source[this.index];
            if (character === '{') depth += 1;
            if (character === '}') depth -= 1;
            this.index += 1;
          }
          return this.source.slice(start, Math.max(start, this.index - 1));
        }

        parseDelimiter() {
          this.skipSpaces();
          if (this.source[this.index] === '\\') {
            this.index += 1;
            const start = this.index;
            while (this.index < this.source.length && /[A-Za-z]/.test(this.source[this.index])) this.index += 1;
            const command = this.source.slice(start, this.index);
            const delimiters = {langle: '&#x27E8;', rangle: '&#x27E9;', lvert: '|', rvert: '|', lVert: '&#x2016;', rVert: '&#x2016;', lbrace: '{', rbrace: '}'};
            return command === '.' ? '' : tag('mo', delimiters[command] || escapeHTML(command), 'stretchy="true"');
          }
          const delimiter = this.source[this.index] || '';
          this.index += delimiter ? 1 : 0;
          return delimiter === '.' ? '' : tag('mo', escapeHTML(delimiter), 'stretchy="true"');
        }

        skipSpaces() {
          while (this.index < this.source.length && /\s/.test(this.source[this.index])) this.index += 1;
        }
      }

      function splitTopLevel(source, kind) {
        const parts = [];
        let start = 0;
        let depth = 0;
        for (let index = 0; index < source.length; index += 1) {
          const character = source[index];
          if (character === '{') depth += 1;
          else if (character === '}') depth = Math.max(0, depth - 1);
          const isSeparator = kind === 'column'
            ? depth === 0 && character === '&'
            : depth === 0 && character === '\\' && source[index + 1] === '\\';
          if (!isSeparator) continue;
          parts.push(source.slice(start, index));
          index += kind === 'row' ? 1 : 0;
          start = index + 1;
        }
        parts.push(source.slice(start));
        return parts;
      }

      function renderEnvironment(source, display) {
        const match = source.trim().match(/^\\begin\{([A-Za-z*]+)\}([\s\S]*)\\end\{\1\}$/);
        if (!match) return null;
        const environment = match[1].replace(/\*$/, '');
        let content = match[2];
        if (environment === 'array' && /^\s*\{[^}]*\}/.test(content)) content = content.replace(/^\s*\{[^}]*\}/, '');
        if (environment === 'equation' || environment === 'displaymath' || environment === 'gather') {
          return new TeXParser(content, true).parse();
        }
        const supported = new Set(['matrix', 'pmatrix', 'bmatrix', 'vmatrix', 'Vmatrix', 'cases', 'aligned', 'align', 'array']);
        if (!supported.has(environment)) return null;
        const rows = splitTopLevel(content, 'row').map(rowSource => {
          const cells = splitTopLevel(rowSource, 'column').map(cell =>
            tag('mtd', new TeXParser(cell, display).parse())
          );
          return tag('mtr', cells.join(''));
        });
        const table = tag('mtable', rows.join(''), environment === 'aligned' || environment === 'align' ? 'columnalign="right left"' : '');
        const fences = {
          pmatrix: ['(', ')'], bmatrix: ['[', ']'], vmatrix: ['|', '|'],
          Vmatrix: ['&#x2016;', '&#x2016;'], cases: ['{', '']
        };
        const fence = fences[environment];
        if (!fence) return table;
        return tag('mrow', tag('mo', fence[0], 'stretchy="true"') + table + (fence[1] ? tag('mo', fence[1], 'stretchy="true"') : ''));
      }

      function latexToMathML(source, display) {
        const latex = String(source || '').trim();
        const content = renderEnvironment(latex, display) || new TeXParser(latex, display).parse();
        const displayValue = display ? 'block' : 'inline';
        return `<math xmlns="http://www.w3.org/1998/Math/MathML" display="${displayValue}" aria-label="${escapeHTML(latex)}">${tag('mrow', content)}</math>`;
      }

      function normalizePlainFormula(source) {
        const superscripts = {
          '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4',
          '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9',
          '⁺': '+', '⁻': '-', 'ⁿ': 'n'
        };
        return String(source || '')
          .replace(/[⁰¹²³⁴-⁹⁺⁻ⁿ]+/g, value =>
            `^{${Array.from(value).map(character => superscripts[character] || character).join('')}}`
          )
          .replace(/\bsqrt\s*(?=\()/gi, '\\sqrt')
          .replace(/\bpi\b/g, '\\pi')
          .replace(/<=/g, '\\le ')
          .replace(/>=/g, '\\ge ')
          .replace(/!=/g, '\\ne ');
      }

      function formulaElementSource(element) {
        const collect = node => {
          if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || '';
          if (node.nodeType !== Node.ELEMENT_NODE) return '';
          const name = node.tagName.toLowerCase();
          if (name === 'sup') return `^{${node.textContent || ''}}`;
          if (name === 'sub') return `_{${node.textContent || ''}}`;
          if (name === 'br') return ' ';
          return Array.from(node.childNodes).map(collect).join('');
        };
        let source = Array.from(element.childNodes).map(collect).join('').trim();
        const wrappers = [
          ['$$', '$$'], ['\\[', '\\]'], ['\\(', '\\)'], ['$', '$']
        ];
        for (const [opening, closing] of wrappers) {
          if (source.startsWith(opening) && source.endsWith(closing) && source.length > opening.length + closing.length) {
            source = source.slice(opening.length, source.length - closing.length).trim();
            break;
          }
        }
        return normalizePlainFormula(source);
      }

      function isEscaped(text, index) {
        let slashCount = 0;
        for (let cursor = index - 1; cursor >= 0 && text[cursor] === '\\'; cursor -= 1) slashCount += 1;
        return slashCount % 2 === 1;
      }

      function findUnescaped(text, marker, start) {
        let index = text.indexOf(marker, start);
        while (index >= 0) {
          if (!isEscaped(text, index)) return index;
          index = text.indexOf(marker, index + marker.length);
        }
        return -1;
      }

      function mathSegments(text) {
        const segments = [];
        let plainStart = 0;
        let index = 0;
        const appendMath = (start, end, source, display) => {
          if (start > plainStart) segments.push({text: text.slice(plainStart, start)});
          segments.push({math: source, display});
          plainStart = end;
          index = end;
        };

        while (index < text.length) {
          if (text.startsWith('\\[', index) && !isEscaped(text, index)) {
            const end = findUnescaped(text, '\\]', index + 2);
            if (end >= 0) {
              appendMath(index, end + 2, text.slice(index + 2, end), true);
              continue;
            }
          }
          if (text.startsWith('\\(', index) && !isEscaped(text, index)) {
            const end = findUnescaped(text, '\\)', index + 2);
            if (end >= 0) {
              appendMath(index, end + 2, text.slice(index + 2, end), false);
              continue;
            }
          }
          if (text.startsWith('$$', index) && !isEscaped(text, index)) {
            const end = findUnescaped(text, '$$', index + 2);
            if (end >= 0) {
              appendMath(index, end + 2, text.slice(index + 2, end), true);
              continue;
            }
          }
          if (text[index] === '$' && text[index + 1] !== '$' && !isEscaped(text, index)) {
            const end = findUnescaped(text, '$', index + 1);
            if (end >= 0 && text[end + 1] !== '$') {
              const source = text.slice(index + 1, end);
              if (source.trim() && !source.includes('\n')) {
                appendMath(index, end + 1, source, false);
                continue;
              }
            }
          }
          index += 1;
        }
        if (plainStart < text.length) segments.push({text: text.slice(plainStart)});
        return segments;
      }

      function renderMath(root) {
        if (!root || typeof document === 'undefined') return 0;
        const formulaElements = [];
        if (root.nodeType === Node.ELEMENT_NODE && root.matches('.np-formula')) formulaElements.push(root);
        if (root.querySelectorAll) formulaElements.push(...root.querySelectorAll('.np-formula'));
        let renderedCount = 0;
        for (const element of formulaElements) {
          if (element.closest('[contenteditable="true"]') || element.querySelector('math')) continue;
          const source = formulaElementSource(element);
          if (!source) continue;
          const template = document.createElement('template');
          template.innerHTML = latexToMathML(source, true);
          element.replaceChildren(template.content.cloneNode(true));
          element.setAttribute('data-notepatch-math-rendered', 'true');
          renderedCount += 1;
        }

        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        const nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        for (const textNode of nodes) {
          const parent = textNode.parentElement;
          if (!parent || parent.closest('math,script,style,pre,code,textarea,[contenteditable="true"]')) continue;
          const segments = mathSegments(textNode.nodeValue || '');
          if (!segments.some(segment => Object.prototype.hasOwnProperty.call(segment, 'math'))) continue;
          const fragment = document.createDocumentFragment();
          for (const segment of segments) {
            if (Object.prototype.hasOwnProperty.call(segment, 'text')) {
              fragment.appendChild(document.createTextNode(segment.text));
            } else {
              const template = document.createElement('template');
              template.innerHTML = latexToMathML(segment.math, segment.display);
              fragment.appendChild(template.content.cloneNode(true));
              renderedCount += 1;
            }
          }
          textNode.replaceWith(fragment);
        }
        return renderedCount;
      }

      scope.__notePatchLatexToMathMLString = latexToMathML;
      scope.__notePatchNormalizePlainFormula = normalizePlainFormula;
      scope.__notePatchFormulaElementSource = formulaElementSource;
      scope.__notePatchMathSegments = mathSegments;
      scope.__notePatchRenderMath = renderMath;
      if (typeof document !== 'undefined') renderMath(document.body);
    })();
    """#
}
