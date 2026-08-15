<?php

namespace Tests\Feature;

use App\Models\Language;
use App\Models\Project;
use App\Models\Translation;
use App\Models\TranslationKey;
use App\Models\TranslationNamespace;
use App\Services\TranslationExporter;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TranslationDomainTest extends TestCase
{
    use RefreshDatabase;

    public function test_namespace_name_must_be_unique_per_project(): void
    {
        $projectA = Project::create(['name' => 'Project A', 'slug' => 'project-a']);
        $projectB = Project::create(['name' => 'Project B', 'slug' => 'project-b']);

        TranslationNamespace::create([
            'project_id' => $projectA->id,
            'name' => 'billing',
        ]);

        TranslationNamespace::create([
            'project_id' => $projectB->id,
            'name' => 'billing',
        ]);

        $this->expectException(QueryException::class);

        TranslationNamespace::create([
            'project_id' => $projectA->id,
            'name' => 'billing',
        ]);
    }

    public function test_translation_key_must_be_unique_per_namespace(): void
    {
        $project = Project::create(['name' => 'Project', 'slug' => 'project']);
        $namespaceA = TranslationNamespace::create([
            'project_id' => $project->id,
            'name' => 'billing',
        ]);
        $namespaceB = TranslationNamespace::create([
            'project_id' => $project->id,
            'name' => 'customers',
        ]);

        TranslationKey::create([
            'namespace_id' => $namespaceA->id,
            'key' => 'invoice_total',
        ]);

        TranslationKey::create([
            'namespace_id' => $namespaceB->id,
            'key' => 'invoice_total',
        ]);

        $this->expectException(QueryException::class);

        TranslationKey::create([
            'namespace_id' => $namespaceA->id,
            'key' => 'invoice_total',
        ]);
    }

    public function test_translation_must_be_unique_per_key_and_language(): void
    {
        $project = Project::create(['name' => 'Project', 'slug' => 'project']);
        $namespace = TranslationNamespace::create([
            'project_id' => $project->id,
            'name' => 'billing',
        ]);
        $key = TranslationKey::create([
            'namespace_id' => $namespace->id,
            'key' => 'invoice_total',
        ]);
        $language = Language::create([
            'code' => 'tr',
            'name' => 'Turkce',
            'is_default' => true,
        ]);

        Translation::create([
            'translation_key_id' => $key->id,
            'language_id' => $language->id,
            'value' => 'Fatura Toplami',
        ]);

        $this->expectException(QueryException::class);

        Translation::create([
            'translation_key_id' => $key->id,
            'language_id' => $language->id,
            'value' => 'Diger deger',
        ]);
    }

    public function test_exporter_outputs_expected_php_json_and_arb_content(): void
    {
        $project = Project::create(['name' => 'Project', 'slug' => 'project']);
        $namespace = TranslationNamespace::create([
            'project_id' => $project->id,
            'name' => 'billing',
        ]);

        $tr = Language::create([
            'code' => 'tr',
            'name' => 'Turkce',
            'is_default' => true,
        ]);

        $en = Language::create([
            'code' => 'en',
            'name' => 'English',
            'is_default' => false,
        ]);

        $keyA = TranslationKey::create([
            'namespace_id' => $namespace->id,
            'key' => 'invoice_total',
        ]);
        $keyB = TranslationKey::create([
            'namespace_id' => $namespace->id,
            'key' => 'status',
        ]);

        Translation::create([
            'translation_key_id' => $keyA->id,
            'language_id' => $tr->id,
            'value' => "Toplam Tutar",
        ]);
        Translation::create([
            'translation_key_id' => $keyB->id,
            'language_id' => $tr->id,
            'value' => "O'dendi",
        ]);

        $namespace->load('keys.translations');

        $php = TranslationExporter::toPhpArray($namespace, $tr);
        $json = TranslationExporter::toJson($namespace, $tr);
        $arb = TranslationExporter::toArb($namespace, $en);

        $this->assertStringContainsString("'invoice_total' => 'Toplam Tutar'", $php);
        $this->assertStringContainsString("'status' => 'O\\'dendi'", $php);

        $jsonData = json_decode($json, true, 512, JSON_THROW_ON_ERROR);
        $this->assertSame('Toplam Tutar', $jsonData['invoice_total']);
        $this->assertSame("O'dendi", $jsonData['status']);

        $arbData = json_decode($arb, true, 512, JSON_THROW_ON_ERROR);
        $this->assertSame('en', $arbData['@@locale']);
        $this->assertSame('', $arbData['invoice_total']);
        $this->assertSame('', $arbData['status']);
    }
}
