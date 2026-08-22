import '../models/media.dart';
import '../models/media_source.dart';

const demoSource = MediaSource(
  id: 'demo',
  name: 'Cineo 演示媒体库',
  type: MediaSourceType.demo,
  baseUrl: 'https://media.example.com',
);

const demoMedia = <MediaItem>[
  MediaItem(
    id: 'afterglow',
    title: '余晖计划',
    description: '在太阳最后一次异常脉冲前，一支小队必须穿越被遗忘的轨道站，找回改变人类命运的讯号。',
    year: 2025,
    kind: MediaKind.movie,
    posterUrl:
        'https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?auto=format&fit=crop&w=720&q=80',
    backdropUrl:
        'https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=1600&q=80',
    genres: ['科幻', '冒险'],
    rating: 8.7,
    duration: Duration(minutes: 118),
    playbackOptions: [
      PlaybackOption(
        id: 'afterglow-hls',
        sourceId: 'demo',
        label: '演示 HLS',
        quality: '1080P',
        url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        isHls: true,
      ),
    ],
  ),
  MediaItem(
    id: 'city-of-mist',
    title: '雾城档案',
    description: '一名调查员在永不散去的浓雾里，追查一桩连接过去与未来的失踪案。',
    year: 2024,
    kind: MediaKind.series,
    posterUrl:
        'https://images.unsplash.com/photo-1519608487953-e999c86e7452?auto=format&fit=crop&w=720&q=80',
    backdropUrl:
        'https://images.unsplash.com/photo-1534796636912-3b95b3ab5986?auto=format&fit=crop&w=1600&q=80',
    genres: ['悬疑', '剧情'],
    rating: 9.1,
    duration: Duration(minutes: 46),
    episodes: [
      Episode(id: 'mist-s1e1', title: '第一集：雾的边界', season: 1, number: 1),
      Episode(id: 'mist-s1e2', title: '第二集：无声来电', season: 1, number: 2),
      Episode(id: 'mist-s1e3', title: '第三集：回声', season: 1, number: 3),
    ],
    playbackOptions: [
      PlaybackOption(
        id: 'mist-hls',
        sourceId: 'demo',
        label: '演示 HLS',
        quality: '720P',
        url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        isHls: true,
      ),
    ],
  ),
  MediaItem(
    id: 'paper-wings',
    title: '纸翼飞行',
    description: '两个陌生人在漫长的列车旅途中，写下了一段从未寄出的故事。',
    year: 2023,
    kind: MediaKind.movie,
    posterUrl:
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=720&q=80',
    backdropUrl:
        'https://images.unsplash.com/photo-1500534623283-312aade485b7?auto=format&fit=crop&w=1600&q=80',
    genres: ['爱情', '剧情'],
    rating: 7.9,
    duration: Duration(minutes: 102),
  ),
  MediaItem(
    id: 'blue-hour',
    title: '蓝色时刻',
    description: '午夜电台主持人接到一通来自二十年前的电话。',
    year: 2025,
    kind: MediaKind.series,
    posterUrl:
        'https://images.unsplash.com/photo-1519681393784-d120267933ba?auto=format&fit=crop&w=720&q=80',
    backdropUrl:
        'https://images.unsplash.com/photo-1483347756197-71ef80e95f73?auto=format&fit=crop&w=1600&q=80',
    genres: ['惊悚', '剧情'],
    rating: 8.2,
    duration: Duration(minutes: 51),
  ),
  MediaItem(
    id: 'tide-line',
    title: '潮汐线',
    description: '海洋学家在深海发现一座不该存在的城市。',
    year: 2024,
    kind: MediaKind.movie,
    posterUrl:
        'https://images.unsplash.com/photo-1518709594023-6eab9bab7b23?auto=format&fit=crop&w=720&q=80',
    backdropUrl:
        'https://images.unsplash.com/photo-1498623116890-37e912163d5d?auto=format&fit=crop&w=1600&q=80',
    genres: ['科幻', '悬疑'],
    rating: 8.4,
    duration: Duration(minutes: 110),
  ),
];
