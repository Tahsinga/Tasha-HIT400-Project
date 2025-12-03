import 'package:flutter/material.dart';
import '../services/vector_db.dart';

class ChunksViewerPage extends StatefulWidget {
  final String bookId;
  final String bookName;

  const ChunksViewerPage({
    super.key,
    required this.bookId,
    required this.bookName,
  });

  @override
  State<ChunksViewerPage> createState() => _ChunksViewerPageState();
}

class _ChunksViewerPageState extends State<ChunksViewerPage> {
  late Future<List<Map<String, dynamic>>> _chunksFuture;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allChunks = [];
  List<Map<String, dynamic>> _filteredChunks = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _chunksFuture = VectorDB.chunksForBook(widget.bookId);
    _chunksFuture.then((chunks) {
      setState(() {
        _allChunks = chunks;
        _filteredChunks = List.from(_allChunks);
      });
    });
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _filteredChunks = List.from(_allChunks);
      } else {
        _filteredChunks = _allChunks
            .where((chunk) {
              final text = (chunk['text'] ?? '').toString().toLowerCase();
              return text.contains(query);
            })
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chunks: ${widget.bookName}'),
        elevation: 0,
        backgroundColor: Colors.blue[600],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _chunksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error loading chunks: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {
                      _chunksFuture = VectorDB.chunksForBook(widget.bookId);
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (_allChunks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No chunks indexed for this book yet.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Index the book to see its chunks.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search chunks...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _isSearching
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              // Stats
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.blue[50],
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total: ${_allChunks.length} chunks',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_isSearching)
                      Text(
                        'Showing: ${_filteredChunks.length}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              // Chunks list
              Expanded(
                child: _filteredChunks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No chunks match "${_searchController.text}"',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _filteredChunks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final chunk = _filteredChunks[index];
                          final chunkText =
                              (chunk['text'] ?? '').toString();
                          final startPage =
                              chunk['start_page'] ?? chunk['page'] ?? 'N/A';
                          final endPage = chunk['end_page'] ?? startPage ?? 'N/A';
                          final chunkId = chunk['id'] ?? '?';

                          return _ChunkCard(
                            chunkId: chunkId,
                            pageRange: '$startPage-$endPage',
                            text: chunkText,
                            index: index + 1,
                            total: _filteredChunks.length,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChunkCard extends StatefulWidget {
  final dynamic chunkId;
  final String pageRange;
  final String text;
  final int index;
  final int total;

  const _ChunkCard({
    required this.chunkId,
    required this.pageRange,
    required this.text,
    required this.index,
    required this.total,
  });

  @override
  State<_ChunkCard> createState() => _ChunkCardState();
}

class _ChunkCardState extends State<_ChunkCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.text.length > 150
        ? widget.text.substring(0, 150) + '...'
        : widget.text;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with metadata
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue[600],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${widget.index}/${widget.total}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chunk ID: ${widget.chunkId}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Pages: ${widget.pageRange}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber[800],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.grey[500],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Preview or full text
              Text(
                _isExpanded ? widget.text : preview,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[800],
                  height: 1.5,
                ),
              ),
              if (_isExpanded) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatItem(
                        label: 'Characters',
                        value: widget.text.length.toString(),
                      ),
                      _StatItem(
                        label: 'Words',
                        value: widget.text.split(RegExp(r'\s+')).length
                            .toString(),
                      ),
                      _StatItem(
                        label: 'Lines',
                        value: widget.text.split('\n').length.toString(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
