# Organizador

App Flutter para cadastrar compromissos, obrigacoes e contas com lembretes na data certa.

## Organizador v1

- Cadastro de compromisso com titulo, descricao, categoria, data e horario.
- Valor opcional para contas e pagamentos.
- Status de pendente, concluido ou pago.
- Lembretes locais na hora, 15 minutos antes, 1 hora antes, 1 dia antes e 1 semana antes.
- Dados sensiveis opcionais, como e-mail, login, senha e observacoes protegidas.
- Armazenamento local: `SharedPreferences` para dados comuns e `flutter_secure_storage` para dados sensiveis.
- Autenticacao local por biometria/PIN quando disponivel antes de mostrar dados protegidos.
- Projeto criado para Android, iOS, Web, macOS, Windows e Linux. A primeira versao foca mobile.

## Rodando

```sh
flutter pub get
flutter run
```

## Validacao

```sh
flutter analyze
flutter test
flutter build web --release
```

## Proximos passos

- Sincronizacao em nuvem com login.
- Repeticao automatica de compromissos mensais, semanais e anuais.
- Busca, filtros avancados e anexos.
- Exportacao/backup dos dados.
