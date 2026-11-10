import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/web/web_theme.dart';
import 'web_empty_state.dart';
import 'web_skeleton.dart';

/// One column of a [WebDataTable]: how to render its header, how to render
/// each cell, and (optionally) how to compare rows for sorting.
class WebTableColumn<T> {
  final String label;
  final double flex;
  final Comparable Function(T item)? sortValue;
  final Widget Function(BuildContext context, T item) cellBuilder;

  const WebTableColumn({
    required this.label,
    required this.cellBuilder,
    this.flex = 1,
    this.sortValue,
  });
}

/// A modern sortable/searchable/paginated table used by every list-heavy
/// web screen (fee ledger, user management, class lists, etc). Renders as a
/// plain [Column] rather than an internally-scrolling list, so it composes
/// naturally inside a screen's existing outer page scroll — the same
/// pattern every screen already uses today.
class WebDataTable<T> extends StatefulWidget {
  final List<T> items;
  final List<WebTableColumn<T>> columns;
  final bool loading;
  final String Function(T item)? searchText;
  final String searchHint;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final List<Widget>? headerActions;
  final int rowsPerPage;
  final void Function(T item)? onRowTap;

  const WebDataTable({
    super.key,
    required this.items,
    required this.columns,
    this.loading = false,
    this.searchText,
    this.searchHint = 'Search...',
    this.emptyIcon = Icons.inbox_rounded,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage = 'No records match your current view.',
    this.headerActions,
    this.rowsPerPage = 10,
    this.onRowTap,
  });

  @override
  State<WebDataTable<T>> createState() => _WebDataTableState<T>();
}

class _WebDataTableState<T> extends State<WebDataTable<T>> {
  String _query = '';
  int? _sortIndex;
  bool _sortAsc = true;
  int _page = 0;

  List<T> get _filtered {
    var list = widget.items;
    if (widget.searchText != null && _query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list
          .where((e) => widget.searchText!(e).toLowerCase().contains(q))
          .toList();
    }
    final sortIndex = _sortIndex;
    if (sortIndex != null) {
      final col = widget.columns[sortIndex];
      if (col.sortValue != null) {
        list = [...list]..sort((a, b) {
            final cmp =
                Comparable.compare(col.sortValue!(a), col.sortValue!(b));
            return _sortAsc ? cmp : -cmp;
          });
      }
    }
    return list;
  }

  @override
  void didUpdateWidget(covariant WebDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) _page = 0;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final totalPages =
        (filtered.length / widget.rowsPerPage).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(0, totalPages - 1);
    final start = page * widget.rowsPerPage;
    final pageItems = filtered.skip(start).take(widget.rowsPerPage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.searchText != null || widget.headerActions != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                if (widget.searchText != null)
                  Expanded(child: _searchBox(context)),
                if (widget.headerActions != null) ...[
                  const SizedBox(width: 12),
                  ...widget.headerActions!,
                ],
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: context.appColors.border.withValues(alpha: 0.5)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.loading)
                const Padding(
                    padding: EdgeInsets.all(20), child: WebSkeletonTable())
              else if (filtered.isEmpty)
                WebEmptyState(
                    icon: widget.emptyIcon,
                    title: widget.emptyTitle,
                    message: widget.emptyMessage)
              else ...[
                _headerRow(context),
                for (int i = 0; i < pageItems.length; i++)
                  _row(context, pageItems[i], i != pageItems.length - 1),
                if (totalPages > 1)
                  _pagination(context, page, totalPages, filtered.length),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchBox(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TextField(
        onChanged: (v) => setState(() {
          _query = v;
          _page = 0;
        }),
        style: TextStyle(fontSize: 13, color: context.appColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.searchHint,
          hintStyle:
              TextStyle(fontSize: 13, color: context.appColors.textMuted),
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: context.appColors.textMuted),
          filled: true,
          fillColor: context.webColors.scrollTrack,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _headerRow(BuildContext context) {
    return Container(
      color: context.webColors.scrollTrack,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          for (int i = 0; i < widget.columns.length; i++)
            Expanded(
              flex: widget.columns[i].flex.round().clamp(1, 999),
              child: InkWell(
                onTap: widget.columns[i].sortValue == null
                    ? null
                    : () => setState(() {
                          if (_sortIndex == i) {
                            _sortAsc = !_sortAsc;
                          } else {
                            _sortIndex = i;
                            _sortAsc = true;
                          }
                        }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(widget.columns[i].label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: context.appColors.textMuted)),
                    ),
                    if (_sortIndex == i) ...[
                      const SizedBox(width: 4),
                      Icon(
                          _sortAsc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 13,
                          color: context.appColors.accentText),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, T item, bool divider) {
    return _HoverRow(
      onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(item),
      showDivider: divider,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            for (final col in widget.columns)
              Expanded(
                  flex: col.flex.round().clamp(1, 999),
                  child: col.cellBuilder(context, item)),
          ],
        ),
      ),
    );
  }

  Widget _pagination(
      BuildContext context, int page, int totalPages, int totalItems) {
    final rangeEnd = ((page + 1) * widget.rowsPerPage).clamp(0, totalItems);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: context.appColors.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${page * widget.rowsPerPage + 1}-$rangeEnd of $totalItems',
              style: TextStyle(
                  fontSize: 12, color: context.appColors.textSecondary)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                onPressed:
                    page > 0 ? () => setState(() => _page = page - 1) : null,
              ),
              Text('${page + 1} / $totalPages',
                  style: TextStyle(
                      fontSize: 12, color: context.appColors.textSecondary)),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                onPressed: page < totalPages - 1
                    ? () => setState(() => _page = page + 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HoverRow extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool showDivider;

  const _HoverRow({required this.child, this.onTap, this.showDivider = false});

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        decoration: BoxDecoration(
          color: _hovering ? context.webColors.hoverTint : Colors.transparent,
          border: widget.showDivider
              ? Border(
                  bottom: BorderSide(
                      color: context.appColors.border.withValues(alpha: 0.35)))
              : null,
        ),
        child: InkWell(onTap: widget.onTap, child: widget.child),
      ),
    );
  }
}
