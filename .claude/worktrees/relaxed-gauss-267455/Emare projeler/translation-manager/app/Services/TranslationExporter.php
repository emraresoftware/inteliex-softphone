<?php

namespace App\Services;

use App\Models\Language;
use App\Models\Project;
use App\Models\TranslationNamespace;

/**
 * Bir projenin belirli modül + dil kombinasyonunu farklı formatlara export eder.
 */
class TranslationExporter
{
    /**
     * Namespace + dil kombinasyonu icin key => value map'i uretir.
     * Iliskiler preload edilmis ise ek sorgu atmaz.
     */
    protected static function buildPairs(TranslationNamespace $namespace, Language $language): array
    {
        $keys = $namespace->relationLoaded('keys')
            ? $namespace->keys
            : $namespace->keys()->with('translations')->get();

        $pairs = [];

        foreach ($keys as $key) {
            $translations = $key->relationLoaded('translations')
                ? $key->translations
                : $key->translations()->get();

            $pairs[$key->key] = $translations->firstWhere('language_id', $language->id)?->value ?? '';
        }

        return $pairs;
    }

    /**
     * Laravel PHP array formatı: lang/tr/faturalar.php
     * return: dosya içeriği (string)
     */
    public static function toPhpArray(TranslationNamespace $namespace, Language $language): string
    {
        $pairs = self::buildPairs($namespace, $language);

        $export = "<?php\n\nreturn [\n\n";
        foreach ($pairs as $k => $v) {
            $escapedKey = str_replace("'", "\\'", $k);
            $escaped = str_replace("'", "\\'", $v);
            $export .= "    '{$escapedKey}' => '{$escaped}',\n";
        }
        $export .= "];\n";

        return $export;
    }

    /**
     * JSON formatı (React/Next.js i18next):
     * public/locales/tr/faturalar.json
     */
    public static function toJson(TranslationNamespace $namespace, Language $language): string
    {
        $pairs = self::buildPairs($namespace, $language);

        return json_encode($pairs, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    }

    /**
     * Flutter ARB formatı: app_tr.arb
     */
    public static function toArb(TranslationNamespace $namespace, Language $language): string
    {
        $pairs = self::buildPairs($namespace, $language);
        $data = ['@@locale' => $language->code];
        foreach ($pairs as $key => $value) {
            $data[$key] = $value;
        }

        return json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    }

    /**
     * Projenin tüm namespace + dil kombinasyonlarını ZIP olarak export et.
     * format: 'php' | 'json' | 'arb'
     */
    public static function exportProjectAsZip(Project $project, string $format = 'php'): string
    {
        $zipPath = storage_path("app/exports/{$project->slug}_{$format}_" . now()->format('YmdHis') . '.zip');

        if (! is_dir(dirname($zipPath))) {
            mkdir(dirname($zipPath), 0755, true);
        }

        $zip = new \ZipArchive();
        $openResult = $zip->open($zipPath, \ZipArchive::CREATE | \ZipArchive::OVERWRITE);
        if ($openResult !== true) {
            throw new \RuntimeException('ZIP dosyasi olusturulamadi. Kod: ' . $openResult);
        }

        $languages = Language::all();
        $namespaces = $project->namespaces()->with('keys.translations')->get();

        foreach ($languages as $lang) {
            foreach ($namespaces as $ns) {
                switch ($format) {
                    case 'php':
                        $content  = self::toPhpArray($ns, $lang);
                        $filename = "lang/{$lang->code}/{$ns->name}.php";
                        break;
                    case 'arb':
                        $content  = self::toArb($ns, $lang);
                        $filename = "arb/{$lang->code}/{$ns->name}.arb";
                        break;
                    default: // json / i18next
                        $content  = self::toJson($ns, $lang);
                        $filename = "locales/{$lang->code}/{$ns->name}.json";
                }

                $zip->addFromString($filename, $content);
            }
        }

        $zip->close();

        return $zipPath;
    }
}
