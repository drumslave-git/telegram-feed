import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rules/rules.dart';

import 'rule_builder_model.dart';

/// A condition on the words of a post, edited as the visual builder (groups of terms joined
/// by OR, terms inside a group by AND) or as the text form `("bitcoin" OR btc) AND NOT
/// airdrop`. The rule editor and a feed's filter both edit their conditions with it.
final class ConditionController extends ChangeNotifier {
  ConditionController([Expr? initial]) {
    if (initial == null || isMatchAll(initial)) return;
    final m = BuilderModel.fromExpr(initial);
    if (m != null) {
      _model = m;
    } else {
      _textMode = true;
    }
    text.text = RuleParser.format(initial);
  }

  /// A stored condition that could not be read: its source to rewrite as text.
  ConditionController.unreadable(String source) {
    _textMode = true;
    text.text = source;
    _error = 'Stored condition could not be parsed; rewrite it.';
  }

  /// The text form's field.
  final text = TextEditingController();

  bool _textMode = false;
  BuilderModel _model = BuilderModel.empty;
  String? _error;

  bool get textMode => _textMode;
  BuilderModel get model => _model;

  /// What is wrong with the text form, shown under it.
  String? get error => _error;

  /// No condition at all, `And([])`: every post matches it.
  static bool isMatchAll(Expr e) => e is And && e.items.isEmpty;

  /// No word typed in the active editor.
  bool get blank => _textMode
      ? text.text.trim().isEmpty
      : _model.groups.every((g) => g.every((t) => t.text.trim().isEmpty));

  /// What the editor holds, as the text form writes it: a change makes it differ.
  String get snapshot => _textMode ? text.text.trim() : _formatModel(_model);

  /// The builder's terms as the text form writes them, leaving out rows without words.
  static String _formatModel(BuilderModel m) {
    final filled = m.withoutBlankTerms();
    return filled == null ? '' : RuleParser.format(filled.toExpr());
  }

  set model(BuilderModel m) {
    _model = m;
    notifyListeners();
  }

  /// The text form was typed in: the error it showed is about the old words.
  void edited() {
    _error = null;
    notifyListeners();
  }

  /// Empties both editors and goes back to the builder.
  void clear() {
    _model = BuilderModel.empty;
    _textMode = false;
    _error = null;
    text.clear();
    notifyListeners();
  }

  /// The condition, or null with the error shown. Blank is `And([])`, which every post
  /// matches. Rows of the builder without a word are left out, as the switch to the text
  /// form leaves them out.
  Expr? condition() {
    if (blank) return const And([]);
    if (_textMode) {
      try {
        final e = RuleParser.parse(text.text);
        _error = null;
        notifyListeners();
        return e;
      } on FormatException catch (e) {
        _showSyntaxError(e);
        return null;
      }
    }
    final filled = _model.withoutBlankTerms();
    return filled == null ? const And([]) : filled.toExpr();
  }

  /// Switches between the builder and the text form. The words typed so far go along;
  /// a condition too nested for the builder stays text and says so.
  void switchMode(bool toText) {
    if (toText == _textMode) return;
    if (toText) {
      text.text = _formatModel(_model);
      _textMode = true;
      _error = null;
      notifyListeners();
      return;
    }
    if (text.text.trim().isEmpty) {
      _model = BuilderModel.empty;
      _textMode = false;
      _error = null;
      notifyListeners();
      return;
    }
    try {
      final m = BuilderModel.fromExpr(RuleParser.parse(text.text));
      if (m == null) {
        _error = 'Too nested for the builder; keep editing as text.';
        notifyListeners();
        return;
      }
      _model = m;
      _textMode = false;
      _error = null;
      notifyListeners();
    } on FormatException catch (e) {
      _showSyntaxError(e);
    }
  }

  /// A parser error in words, without the parser's prefix and position; the cursor shows
  /// the position instead.
  static String _syntaxMessage(FormatException e) {
    var m = e.message.replaceFirst('rule syntax: ', '');
    m = m.replaceFirst(RegExp(r' at \d+$'), '');
    if (m.isEmpty) return 'This condition cannot be read.';
    return '${m[0].toUpperCase()}${m.substring(1)} where the cursor is.';
  }

  void _showSyntaxError(FormatException e) {
    final at = e.offset;
    if (at != null && at >= 0 && at <= text.text.length) {
      text.selection = TextSelection.collapsed(offset: at);
    }
    _error = _syntaxMessage(e);
    notifyListeners();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }
}

/// The condition's heading with the Builder / Text switch, an optional note, and the editor
/// that is switched on.
class ConditionEditor extends StatelessWidget {
  const ConditionEditor({
    super.key,
    required this.controller,
    required this.title,
    this.note,
  });
  final ConditionController controller;
  final Widget title;

  /// Said between the heading and the editor. Always given a slot, so a note that comes
  /// and goes as the first word is typed does not move the field being typed in.
  final Widget? note;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            title,
            const Spacer(),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Builder')),
                ButtonSegment(value: true, label: Text('Text')),
              ],
              selected: {controller.textMode},
              onSelectionChanged: (s) => controller.switchMode(s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        note ?? const SizedBox.shrink(),
        if (controller.textMode)
          TextField(
            controller: controller.text,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: '("bitcoin" OR btc) AND NOT airdrop',
              helperText:
                  'Words or "phrases" joined by AND, OR, NOT, with brackets.',
              helperMaxLines: 2,
              errorText: controller.error,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: 'Syntax',
                icon: const Icon(Icons.help_outline),
                onPressed: () => showConditionSyntax(context),
              ),
            ),
            onChanged: (_) => controller.edited(),
          )
        else
          ConditionBuilder(
            model: controller.model,
            onChanged: (m) => controller.model = m,
          ),
      ],
    ),
  );
}

/// The whole syntax of the text form, which does not fit under the field.
void showConditionSyntax(BuildContext context) => unawaited(
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            'Writing a condition',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final (example, meaning) in const [
            ('bitcoin', 'the word, wherever it stands'),
            ('"interest rate"', 'those words next to each other'),
            ('bitcoin AND etf', 'both have to be there'),
            ('bitcoin OR btc', 'either one is enough'),
            ('NOT airdrop', 'the post must not have it'),
            ('(a OR b) AND c', 'brackets group the parts'),
            ('~rate', 'also inside longer words, like "rates"'),
            ('=Fed', 'exactly that spelling, capitals included'),
          ])
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(example),
              subtitle: Text(meaning),
            ),
        ],
      ),
    ),
  ),
);

/// Groups joined by OR; terms inside a group joined by AND.
class ConditionBuilder extends StatelessWidget {
  const ConditionBuilder({
    super.key,
    required this.model,
    required this.onChanged,
  });
  final BuilderModel model;
  final ValueChanged<BuilderModel> onChanged;

  void _update(int g, int t, BuilderTerm term) {
    final groups = [
      for (final x in model.groups) [...x],
    ];
    groups[g][t] = term;
    onChanged(BuilderModel(groups));
  }

  void _remove(int g, int t) {
    final groups = [
      for (final x in model.groups) [...x],
    ];
    groups[g].removeAt(t);
    if (groups[g].isEmpty) groups.removeAt(g);
    // Nothing left is no condition, which is a state of its own.
    onChanged(BuilderModel(groups));
  }

  void _addTerm(int g) {
    final groups = [
      for (final x in model.groups) [...x],
    ];
    groups[g].add(const BuilderTerm(text: ''));
    onChanged(BuilderModel(groups));
  }

  void _addGroup() => onChanged(
    BuilderModel([
      ...model.groups,
      [const BuilderTerm(text: '')],
    ]),
  );

  @override
  Widget build(BuildContext context) {
    if (model.groups.isEmpty) {
      // No blank row with a delete button under a line that says there is no condition.
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _addGroup,
          icon: const Icon(Icons.add),
          label: const Text('Add a term'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < model.groups.length; g++) ...[
          if (g > 0)
            const Center(
              child: Padding(padding: EdgeInsets.all(4), child: Text('OR')),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  for (var t = 0; t < model.groups[g].length; t++) ...[
                    if (t > 0) const Text('AND'),
                    _TermRow(
                      term: model.groups[g][t],
                      onChanged: (term) => _update(g, t, term),
                      onRemove: () => _remove(g, t),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _addTerm(g),
                      icon: const Icon(Icons.add),
                      label: const Text('AND another word'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        TextButton.icon(
          onPressed: _addGroup,
          icon: const Icon(Icons.add),
          label: const Text('OR alternative'),
        ),
      ],
    );
  }
}

class _TermRow extends StatefulWidget {
  const _TermRow({
    required this.term,
    required this.onChanged,
    required this.onRemove,
  });
  final BuilderTerm term;
  final ValueChanged<BuilderTerm> onChanged;
  final VoidCallback onRemove;

  @override
  State<_TermRow> createState() => _TermRowState();
}

class _TermRowState extends State<_TermRow> {
  late final _ctl = TextEditingController(text: widget.term.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // A term that was just added takes the cursor, also away from the name field, so
    // the word can be typed right after "Add a term".
    if (widget.term.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(_TermRow old) {
    super.didUpdateWidget(old);
    // A row above was removed and this state now shows another term: its own words.
    if (widget.term.text != _ctl.text) {
      _ctl.value = TextEditingValue(
        text: widget.term.text,
        selection: TextSelection.collapsed(offset: widget.term.text.length),
      );
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _option(String label, bool on, BuilderTerm Function() toggled) =>
      FilterChip(
        label: Text(label),
        selected: on,
        onSelected: (_) => widget.onChanged(toggled()),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.term;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctl,
                focusNode: _focus,
                decoration: InputDecoration(
                  hintText: t.negated
                      ? 'word it must not have'
                      : 'word or phrase',
                  isDense: true,
                ),
                onChanged: (v) => widget.onChanged(t.copyWith(text: v)),
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: widget.onRemove,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _option(
              'Must not contain',
              t.negated,
              () => t.copyWith(negated: !t.negated),
            ),
            _option(
              'Whole word',
              t.wholeWord,
              () => t.copyWith(wholeWord: !t.wholeWord),
            ),
            _option(
              'Match case',
              t.caseSensitive,
              () => t.copyWith(caseSensitive: !t.caseSensitive),
            ),
          ],
        ),
      ],
    );
  }
}
