import 'dart:math';

import 'package:file/file.dart';
import 'package:neoansi/neoansi.dart';

import '../command_result.dart';
import '../config.dart';
import '../proto/puro.pb.dart';
import '../provider.dart';
import '../terminal.dart';
import 'default.dart';
import 'releases.dart';
import 'version.dart';

class EnvironmentInfoResult {
  EnvironmentInfoResult(this.environment, this.version);

  final EnvConfig environment;
  final FlutterVersion? version;

  EnvironmentInfoModel toModel() {
    return EnvironmentInfoModel(
      name: environment.name,
      path: environment.envDir.path,
      version: version?.toModel(),
    );
  }
}

class ListEnvironmentResult extends CommandResult {
  ListEnvironmentResult({
    required this.results,
    required this.projectEnvironment,
    required this.globalEnvironment,
  });

  final List<EnvironmentInfoResult> results;
  final String? projectEnvironment;
  final String? globalEnvironment;

  @override
  bool get success => true;

  @override
  CommandMessage get message {
    return CommandMessage.format(
      (format) {
        if (results.isEmpty) {
          return 'No environments, use `puro create` to create one';
        }
        final lines = <String>[];

        for (final result in results) {
          final name = result.environment.name;
          if (name == projectEnvironment) {
            lines.add(
              format.color(
                '* $name',
                foregroundColor: Ansi8BitColor.green,
                bold: true,
              ),
            );
          } else if (name == globalEnvironment && projectEnvironment == null) {
            lines.add(
              format.color(
                '~ $name',
                foregroundColor: Ansi8BitColor.green,
                bold: true,
              ),
            );
          } else if (name == globalEnvironment) {
            lines.add('~ $name');
          } else {
            lines.add('  $name');
          }
        }

        final linePadding =
            lines.fold<int>(0, (v, e) => max(v, stripAnsiEscapes(e).length));

        return [
          'Environments:',
          for (var i = 0; i < lines.length; i++)
            padRightColored(lines[i], linePadding) +
                format.color(
                  ' (${results[i].environment.exists ? results[i].version ?? 'unknown' : 'not installed'})',
                  foregroundColor: Ansi8BitColor.grey,
                ),
          '',
          'Use `puro create <name>` to create an environment, or `puro use <name>` to switch',
        ].join('\n');
      },
      type: CompletionType.info,
    );
  }

  @override
  late final model = CommandResultModel(
    environmentList: EnvironmentListModel(
      environments: [
        for (final info in results) info.toModel(),
      ],
      projectEnvironment: projectEnvironment,
      globalEnvironment: globalEnvironment,
    ),
  );
}

/// Lists all available environments
Future<ListEnvironmentResult> listEnvironments({
  required Scope scope,
}) async {
  final config = PuroConfig.of(scope);
  final results = <EnvironmentInfoResult>[];

  for (final name in pseudoEnvironmentNames) {
    final environment = config.getEnv(name);
    FlutterVersion? version;
    if (environment.exists) {
      version = await getEnvironmentFlutterVersion(
        scope: scope,
        environment: environment,
      );
    }
    results.add(EnvironmentInfoResult(environment, version));
  }

  if (config.envsDir.existsSync()) {
    for (final childEntity in config.envsDir.listSync()) {
      if (childEntity is! Directory ||
          !isValidName(childEntity.basename) ||
          childEntity.basename == 'default') {
        continue;
      }
      final environment = config.getEnv(childEntity.basename);
      if (pseudoEnvironmentNames.contains(environment.name)) continue;
      final version = await getEnvironmentFlutterVersion(
        scope: scope,
        environment: environment,
      );
      results.add(EnvironmentInfoResult(environment, version));
    }
  }

  return ListEnvironmentResult(
    results: results,
    projectEnvironment: config.tryGetProjectEnv()?.name,
    globalEnvironment: await getDefaultEnvName(scope: scope),
  );
}
