# Сторонние компоненты

## WindUI

Автор: Footagesus (Footages). Закреплённый релиз: 1.6.66.

- [Исходный проект](https://github.com/Footagesus/WindUI)
- [Файл релиза](https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua)
- [Полный текст MIT](licenses/WindUI-MIT.txt)

Файл включён без изменений в `vendor/`. Встроенные функции библиотеки могут обращаться к её внешним ресурсам, например набору иконок. Указание By SyneX относится к SynHub, авторство библиотеки сохраняется.

## Русский словарь

Производный список существительных в `data/dictionaries/` распространяется по [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

Источники и преобразования:

1. [Harrix / Russian-Nouns](https://github.com/Harrix/Russian-Nouns), Harrix и участники проекта, MIT. Исходный список очищен и отфильтрован по морфологии. [Текст лицензии](licenses/Harrix-MIT.txt).
2. [wordfreq 3.1.1](https://github.com/rspeer/wordfreq), Robyn Speer. Частотные данные CC BY-SA 4.0. Использована частотность русского языка с поправкой на вероятность разбора слова как существительного; список отсортирован по убыванию. [Лицензия](licenses/wordfreq-LICENSE.txt), [источники и уведомления](licenses/wordfreq-NOTICE.md).
3. [OpenCorpora](https://opencorpora.org/), участники проекта, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). Морфологическая фильтрация через pymorphy3 2.0.6 и pymorphy3-dicts-ru 2.4.417150.4580142. Включён только результат фильтрации.

Исключены имена, сокращения и неподходящие словоформы. Параметры и контрольная сумма исходного списка приведены в [метаданных](data/dictionaries/metadata.json). Частотность отражает языковые корпуса; словарь конкретной игры может отличаться.
