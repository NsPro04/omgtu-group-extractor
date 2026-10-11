#include <httplib/httplib.h>
#include <oneapi/tbb/parallel_for_each.h>
#include <oneapi/tbb/concurrent_hash_map.h>
#include <spdlog/spdlog.h>
#include <nlohmann/json.hpp>
#include <asio.hpp>

#include <string>
#include <string_view>
#include <vector>
#include <format>

using namespace nlohmann;
using namespace std::string_view_literals;

int main() {
  asio::io_context io_context;
  asio::stream_file file(io_context, "file.json", asio::file_base::create | asio::file_base::write_only | asio::file_base::truncate | asio::file_base::sync_all_on_write);
  asio::write(file, asio::buffer("{\n"sv));

  for (size_t group_id = 300; group_id <= 400; ++group_id) {
    spdlog::info("group_id: {}", group_id);

    tbb::concurrent_hash_map<std::string, std::string> data__groups;
    tbb::concurrent_hash_map<std::string, std::pair<std::string, std::string>> data__subgroups;

    const static std::vector<std::string> months = {
        "?start=2026.09.1&finish=2026.09.30",
        "?start=2026.10.1&finish=2026.10.31",
        "?start=2026.11.1&finish=2026.11.30",
        "?start=2026.12.1&finish=2026.12.31",

        "?start=2027.1.1&finish=2027.1.31",
        "?start=2027.2.1&finish=2027.2.28",
        "?start=2027.3.1&finish=2027.3.31",
        "?start=2027.4.1&finish=2027.4.30",
        "?start=2027.5.1&finish=2027.5.31",
        "?start=2027.6.1&finish=2027.6.30"};

    tbb::parallel_for_each(months, [group_id, &data__groups, &data__subgroups](const std::string &month) {
      for (size_t try_count = 0; try_count < 5; ++try_count) {
        auto cli = httplib::SSLClient("rasp.omgtu.ru");
        cli.set_connection_timeout(10 * 2);
        cli.set_read_timeout(15 * 2);
        cli.set_write_timeout(15 * 2);

        const std::string url = std::format("/api/schedule/group/{}{}", group_id, month);

        const httplib::Result res = cli.Get(url);

        if (const httplib::Error status = res.error(); !res || status != httplib::Error::Success) {
          if ((try_count + 1) == 5) {
            spdlog::error("try_count == 5: https://rasp.omgtu.ru{}", url);
          }
          continue;
        };

        const httplib::Response response = res.value();

        const json body = json::parse(response.body);

        if (!body.is_array()) {
          spdlog::error("!body.is_array(): https://rasp.omgtu.ru{}", url);
          break;
        }

        for (const auto &schedule : body) {
          if (schedule.contains("listSubGroups") && schedule["listSubGroups"].is_array() && schedule["listSubGroups"].size()) {
            for (const auto &subgroup : schedule["listSubGroups"]) {
              if (subgroup["subgroup_groupOid"] == group_id) {
                std::string subgroupOid = subgroup["subgroupOid"].dump();

                if (!data__subgroups.count(subgroupOid)) {
                  data__subgroups.insert({std::move(subgroupOid), {subgroup["subgroup"], subgroup["subgroup_groupOid"].dump()}});
                }
              }
            }
          } else if (schedule.contains("listGroups") && schedule["listGroups"].is_array() && schedule["listGroups"].size()) {
            for (const auto &group : schedule["listGroups"]) {
              if (group["groupOid"] == group_id) {
                std::string groupOid = group["groupOid"].dump();

                if (!data__groups.count(groupOid)) {
                  data__groups.insert({std::move(groupOid), group["group"]});
                }
              }
            }
          }
        }

        break;
      }
    });

    asio::write(file, asio::buffer("["sv));
    {
      asio::write(file, asio::buffer(R"("groups":)"sv));
      asio::write(file, asio::buffer("["sv));
      for (const auto &[group_id, group_name] : data__groups) {
        asio::write(file, asio::buffer(std::format(R"({{"{}":{{"name":"{}"}}}},)", group_id, group_name)));
      }
      asio::write(file, asio::buffer("]"sv));
    }
    asio::write(file, asio::buffer(", "sv));
    {
      asio::write(file, asio::buffer(R"("subgroups":)"sv));
      asio::write(file, asio::buffer("["sv));
      for (const auto &[subgroup_id, subgroup_data] : data__subgroups) {
        asio::write(file, asio::buffer(std::format(R"({{"{}":{{"name":"{}", "group_id":"{}"}}}},)", subgroup_id, subgroup_data.first, subgroup_data.second)));
      }
      asio::write(file, asio::buffer("]"sv));
    }
    asio::write(file, asio::buffer("},\n"sv));
  }

  asio::write(file, asio::buffer("]"sv));

  return 0;
}