import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/backend_models.dart';
import '../services/backend_api.dart';
import '../widgets/action_badge.dart';
import 'result_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final List<RecognitionRecord> _records = [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<BackendApi>();
    try {
      final page = await api.queryHistory(offset: 0, limit: 50);
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addAll(page.items);
        _total = page.total;
        _hasMore = page.items.length < page.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    final api = context.read<BackendApi>();
    try {
      final page = await api.queryHistory(offset: _records.length, limit: 50);
      if (!mounted) return;
      setState(() {
        _records.addAll(page.items);
        _hasMore = _records.length < page.total;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定删除选中的 ${ids.length} 条识别记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final api = context.read<BackendApi>();
    final result = await api.deleteRecords(ids);
    if (!mounted) return;
    if (result.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：${result.error!.message}')),
      );
      return;
    }
    setState(() => _selected.clear());
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 ${ids.length} 条记录')),
      );
    }
  }

  Future<void> _exportSelected(ReportFormat format) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final api = context.read<BackendApi>();
    final result = await api.exportReport(ReportRequest(recordIds: ids, format: format));
    if (!mounted) return;
    if (result.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：${result.error!.message}')),
      );
      return;
    }
    final r = result.value!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('报告已生成'),
        content: Text(
          '格式：${format.zh}\n'
          '记录数：${r.recordCount}\n'
          '位置：${r.location}\n'
          '类型：${r.mimeType}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showExportSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('导出报告格式', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final format in ReportFormat.values)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text('${format.zh}（${format.name}）'),
                subtitle: Text(format.mimeType),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportSelected(format);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selecting = _selected.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(selecting ? '已选择 ${_selected.length} 条' : '历史记录'),
        actions: [
          if (selecting) ...[
            IconButton(
              tooltip: '导出报告',
              icon: const Icon(Icons.ios_share),
              onPressed: _showExportSheet,
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteSelected,
            ),
            IconButton(
              tooltip: '取消选择',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_selected.clear),
            ),
          ],
        ],
      ),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    final selecting = _selected.isNotEmpty;
    if (_error != null && _records.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_records.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Icon(Icons.history, size: 64, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Center(child: Text('暂无识别记录', style: TextStyle(color: scheme.outline))),
            Center(
              child: Text(
                '完成单图或批量识别后，结果会保存在这里',
                style: TextStyle(fontSize: 12, color: scheme.outlineVariant),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _records.length + 1,
        itemBuilder: (context, index) {
          if (index == _records.length) {
            if (!_hasMore) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text('共 $_total 条记录', style: TextStyle(color: scheme.outline)),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: _loadMore,
                        child: const Text('加载更多'),
                      ),
              ),
            );
          }
          final record = _records[index];
          final result = record.result;
          final selected = _selected.contains(result.recordId);
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: ActionBadge(action: result.action),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      result.action.zh,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _qualityChip(result.quality),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_formatTime(result.createdAtEpochMillis)}\n'
                  '${result.modelInfo.version} · 总耗时 ${result.timing.totalMillis} ms'
                  '${result.warnings.isEmpty ? '' : ' · ${result.warnings.map((w) => w.zh).join('、')}'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              isThreeLine: true,
              trailing: selecting
                  ? Checkbox(
                      value: selected,
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(result.recordId);
                        } else {
                          _selected.remove(result.recordId);
                        }
                      }),
                    )
                  : null,
              onTap: selecting
                  ? () => setState(() {
                        if (selected) {
                          _selected.remove(result.recordId);
                        } else {
                          _selected.add(result.recordId);
                        }
                      })
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ResultDetailPage(result: result),
                        ),
                      ),
              onLongPress: () => setState(() {
                if (selected) {
                  _selected.remove(result.recordId);
                } else {
                  _selected.add(result.recordId);
                }
              }),
            ),
          );
        },
      ),
    );
  }

  Widget _qualityChip(QualityStatus quality) {
    final color = switch (quality) {
      QualityStatus.accepted => Colors.green,
      QualityStatus.lowConfidence => Colors.orange,
      QualityStatus.insufficientKeypoints => Colors.orange,
      QualityStatus.unknownPose => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(quality.zh, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  String _formatTime(int epochMillis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
