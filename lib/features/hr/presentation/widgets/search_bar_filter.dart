import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// Reusable search bar with an optional trailing filter chip area.
///
/// By default keystrokes fire [onChanged] immediately — the current
/// HR employees list already debounces by 300ms inside
/// [EmployeeFilterController]. Other call sites that drive an
/// unbuffered network fetch should pass [debounce] (e.g. `300ms`)
/// to coalesce keystrokes locally and avoid hammering the backend.
class SearchBarFilter extends StatefulWidget {
  final String hint;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final List<Widget> trailing;
  final VoidCallback? onClear;

  /// When non-null, [onChanged] only fires once typing has been quiet
  /// for [debounce]. Use this when the upstream controller doesn't
  /// already coalesce — typically 300ms for free-text fetches.
  final Duration? debounce;

  const SearchBarFilter({
    super.key,
    required this.hint,
    required this.onChanged,
    this.initialValue = '',
    this.trailing = const [],
    this.onClear,
    this.debounce,
  });

  @override
  State<SearchBarFilter> createState() => _SearchBarFilterState();
}

class _SearchBarFilterState extends State<SearchBarFilter> {
  late final TextEditingController _controller;
  bool _hasText = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _hasText = widget.initialValue.isNotEmpty;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // setState for the clear-button visibility — that's synchronous
    // regardless of debouncing so the UI stays responsive.
    setState(() => _hasText = value.isNotEmpty);

    final debounce = widget.debounce;
    if (debounce == null) {
      widget.onChanged(value);
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => widget.onChanged(value));
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() => _hasText = false);
    widget.onChanged('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider, width: 1.2),
              ),
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  suffixIcon: _hasText
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: _clear,
                          tooltip: 'Clear',
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  filled: false,
                ),
              ),
            ),
          ),
          if (widget.trailing.isNotEmpty) ...[
            const SizedBox(width: 8),
            ...widget.trailing,
          ],
        ],
      ),
    );
  }
}
