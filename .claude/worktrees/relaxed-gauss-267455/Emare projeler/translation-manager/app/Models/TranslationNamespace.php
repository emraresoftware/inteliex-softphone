<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class TranslationNamespace extends Model
{
    protected $table = 'namespaces';

    protected $fillable = ['project_id', 'name', 'description'];

    public function project(): BelongsTo
    {
        return $this->belongsTo(Project::class);
    }

    public function keys(): HasMany
    {
        return $this->hasMany(TranslationKey::class, 'namespace_id');
    }
}
