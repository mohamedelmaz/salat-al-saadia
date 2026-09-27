import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../widgets/adhkar_counter_card.dart';

class AdhkarScreen extends StatelessWidget {
  const AdhkarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الأذكار'),
          bottom: const TabBar(
            indicatorColor: AppColors.secondaryGold,
            labelColor: AppColors.secondaryGold,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'أذكار الصباح'),
              Tab(text: 'أذكار المساء'),
              Tab(text: 'أذكار النوم'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildAdhkarList([
              {
                'text':
                    'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ لاَ إِلَهَ إِلاَّ اللَّهُ وَحْدَهُ لاَ شَرِيكَ لَهُ...',
                'virtue': 'من قالها حين يصبح أُعطي خير هذا اليوم.',
                'count': 1
              },
              {
                'text':
                    'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ عَدَدَ خَلْقِهِ، وَرِضَا نَفْسِهِ، وَزِنَةَ عَرْشِهِ، وَمِدَادَ كَلِمَاتِهِ.',
                'virtue': 'تعدل أجوراً عظيمة في الذكر.',
                'count': 3
              },
              {
                'text':
                    'اللَّهُمَّ عَافِنِي فِي بَدَنِي، اللَّهُمَّ عَافِنِي فِي سَمْعِي، اللَّهُمَّ عَافِنِي فِي بَصَرِي.',
                'virtue': 'دعاء العافية وحفظ الجوارح.',
                'count': 3
              },
            ]),
            _buildAdhkarList([
              {
                'text':
                    'أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ لاَ إِلَهَ إِلاَّ اللَّهُ...',
                'virtue': 'حفظ وتحصين المساء.',
                'count': 1
              },
              {
                'text':
                    'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ.',
                'virtue': 'لم يضره شيء حتى يصبح.',
                'count': 3
              },
            ]),
            _buildAdhkarList([
              {
                'text':
                    'بِاسْمِكَ رَبِّ وَضَعْتُ جَنْبِي، وَبِكَ أَرْفَعُهُ، فَإِن أَمْسَكْتَ نَفْسِي فَارْحَمْهَا...',
                'virtue': 'دعاء النوم.',
                'count': 1
              },
              {
                'text': 'اللَّهُمَّ قِنِي عَذَابَكَ يَوْمَ تَبْعَثُ عِبَادَكَ.',
                'virtue': 'يقال ثلاث مرات عند الاضطجاع.',
                'count': 3
              },
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildAdhkarList(List<Map<String, dynamic>> adhkar) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: adhkar.length,
      itemBuilder: (context, index) {
        final item = adhkar[index];
        return AdhkarCounterCard(
          text: item['text'] as String,
          virtue: item['virtue'] as String?,
          maxCount: item['count'] as int,
        );
      },
    );
  }
}
