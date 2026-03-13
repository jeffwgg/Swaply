import 'package:flutter/material.dart';
import 'package:bubble_tab_indicator/bubble_tab_indicator.dart';

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

              const SizedBox(height: 20),

              TabBar(
                dividerColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                isScrollable: true,
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
                      children: const [
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
                  children: [
                    Center(child: Text("Items")),
                    Center(child: Text("Items")),
                    Center(child: Text("Items")),
                    Center(child: Text("Items")),
                    Center(child: Text("Items")),
                    Center(child: Text("Items")),
                    Center(child: Text("Items")),
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
