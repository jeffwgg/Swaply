import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:bubble_tab_indicator/bubble_tab_indicator.dart';

import 'item_detail_screen.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20.0, 50.0, 20.0, 8.0),
          child: Column(
            children: [
              const TextField(
                autofocus: false,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  suffixIcon: Icon(Icons.tune),
                  labelText: 'Search',
                  hintText: 'Search items, trades or sellers',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(10.0)),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              TabBar(
                dividerColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: const BubbleTabIndicator(
                  indicatorHeight: 30.0,
                  indicatorColor: Colors.deepPurple,
                  indicatorRadius: 10.0,
                  tabBarIndicatorSize: TabBarIndicatorSize.tab,
                ),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.format_list_bulleted, size: 18),
                        SizedBox(width: 6),
                        Text("All"),
                      ],
                    ),
                  ),
                  Tab(text: "Electronics"),
                  Tab(text: "Fashion"),
                  Tab(text: "Home"),
                  Tab(text: "Home"),
                  Tab(text: "Home"),
                  Tab(text: "Home"),
                ],
              ),

              const SizedBox(height: 20),

              const Expanded(
                child: TabBarView(
                  children: <Widget>[
                    NestedTabBar('All'),
                    NestedTabBar('Electronics'),
                    NestedTabBar('Fashion'),
                    NestedTabBar('Home'),
                    NestedTabBar('Home'),
                    NestedTabBar('Home'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NestedTabBar extends StatefulWidget {
  const NestedTabBar(this.outerTab, {super.key});

  final String outerTab;

  @override
  State<NestedTabBar> createState() => _NestedTabBarState();
}

class _NestedTabBarState extends State<NestedTabBar>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Color(0xFFE9D5FF),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: TabBar.secondary(
                  isScrollable: false,
                  padding: EdgeInsets.zero,
                  labelPadding: EdgeInsets.symmetric(horizontal: 12),
                  tabAlignment: TabAlignment.fill,
                  dividerColor: Colors.transparent,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  labelColor: Colors.deepPurple,
                  unselectedLabelColor: Colors.deepPurple.shade300,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: EdgeInsets.symmetric(horizontal: 12),
                  indicator: const BubbleTabIndicator(
                    indicatorHeight: 36.0,
                    indicatorColor: Colors.white,
                    indicatorRadius: 10.0,
                  ),
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'All Items'),
                    Tab(text: 'For Sale'),
                    Tab(text: 'For Trade'),
                  ],
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: <Widget>[
              GridView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: 4,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemBuilder: (context, index) {
                  return const ItemCard();
                },
              )
            ],
          ),
        ),
      ],
    );
  }
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (){
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ItemDetailsScreen()),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.asset(
                    'assets/sample.jpeg',
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),

                Positioned(
                  top: 45,
                  left: 10,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'TRADE',
                      style: TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                ),

                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'RM 249.00',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),

                Positioned(
                  top: 10,
                  right: 10,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.favorite_border,
                        color: Colors.deepPurple),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Premium Headphones',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14),
                      SizedBox(width: 4),
                      Text('0.8 miles away'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}