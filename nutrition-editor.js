/* ══════════════════════════════════════════════════════════════
   עורך התזונה — משותף לפאנל המאמן ולפאנל האדמין
   ══════════════════════════════════════════════════════════════
   הקובץ הזה נוצר אחרי ששני הפאנלים החזיקו עותקים נפרדים של אותו
   עורך, ואלה נפרדו: כל פיצ'ר שנוסף אצל המאמן — אופציות לארוחה,
   מיזוג ופיצול, סוג ארוחה, ממוצע האופציות בסכומים — פשוט לא היה
   קיים אצל האדמין, ותפריט עם אופציות הוצג שם חלקית ועם סכומים
   שגויים. מקור אחד מונע את זה מלכתחילה.

   הקובץ נשען על שמות שקיימים בשני הפאנלים: nutritionPlan,
   activeEmail, canEdit, toast, sb, esc, clients, allFoodItems,
   collapsedMeals, saveNutrition, requireEdit, findFood, ensureLibs.
   פאנל שחסר בו אחד מהם מספק אותו כשורה אחת לפני הטעינה.

   נטען כ-<script src> לפני הסקריפט הראשי של העמוד, כדי שההגדרות
   כאן יהיו זמינות בזמן שהעמוד מאתחל.
   ══════════════════════════════════════════════════════════════ */
  /* סיווג המאקרו הדומיננטי של פריט. itemRole נשען עליו, ולכן הוא
     חייב לשבת כאן ולא בפאנל אחד בלבד. */
  function dominantMacro(item) {
    const p = +item.protein||0, c = +item.carbs||0, f = +item.fat||0;
    const kcal = p*4 + c*4 + f*9;
    if (kcal && (p*4)/kcal >= 0.30) return 'protein';
    return c >= f ? 'carbs' : 'fat';
  }

  function renderNutritionEditor() {
    syncVariableMenu();   // תפריט עם אופציות מדליק את הסוויץ' מעצמו
    const el = document.getElementById('nutrition-editor');
    if (!el) return;
    if (!nutritionPlan.length) { el.innerHTML='<div style="color:#444;font-size:0.85rem;padding:8px 0;">אין ארוחות עדיין — לחץ + הוסף ארוחה</div>'; return; }

    const totCal  = planSum('calories');
    const totProt = planSum('protein');
    const totCarb = planSum('carbs');
    const totFat  = planSum('fat');
    const tgCal   = parseInt(document.getElementById('e-cal')?.value)  || 0;
    const tgProt  = parseInt(document.getElementById('e-prot')?.value) || 0;
    const tgCarb  = parseInt(document.getElementById('e-carb')?.value) || 0;
    const tgFat   = parseInt(document.getElementById('e-fat')?.value)  || 0;
    const pct = (v,t) => t ? Math.min(100, Math.round(v/t*100)) : (v>0?100:0);
    const KEYOF = { 'קלוריות':'calories', 'חלבון':'protein', 'פחמימה':'carbs', 'שומן':'fat' };
    const bar = (label, val, tg, color) => `
      <div style="margin-bottom:9px;" data-macro="${KEYOF[label]}">
        <div style="display:flex;justify-content:space-between;font-size:0.75rem;margin-bottom:4px;">
          <span style="font-weight:700;color:${color};">${label}</span>
          <span class="macro-val" style="color:#ccc;">${val}${label==='קלוריות'?'':' ג׳'}${tg ? ` <span style="color:#555;">/ ${tg}</span>` : ''}</span>
        </div>
        <div style="height:6px;background:rgba(255,255,255,0.07);border-radius:3px;overflow:hidden;">
          <div class="macro-fill" style="height:100%;width:${pct(val,tg)}%;background:${color};border-radius:3px;transition:width 0.3s;"></div>
        </div>
      </div>`;

    const macroBar = `
      <div id="nutri-macro-bar" style="background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.07);border-radius:12px;padding:14px 16px;margin-bottom:16px;position:relative;">
        <div id="nutri-save-chip" style="position:absolute;top:10px;left:14px;font-size:0.7rem;font-weight:800;color:#4ade80;opacity:0;transition:opacity .3s;">✓ נשמר</div>
        ${bar('קלוריות', totCal, tgCal, 'var(--orange)')}
        ${bar('חלבון',   totProt, tgProt, '#4ade80')}
        ${bar('פחמימה',  totCarb, tgCarb, '#60a5fa')}
        ${bar('שומן',    totFat,  tgFat,  '#facc15')}
      </div>`;

    const vmSwitch = `<div style="display:flex;align-items:center;gap:9px;margin-bottom:10px;padding:8px 12px;border-radius:10px;background:rgba(96,180,255,0.06);border:1px solid rgba(96,180,255,0.2);">
      <label style="display:flex;align-items:center;gap:7px;cursor:pointer;font-size:0.8rem;font-weight:700;color:#7ec8ff;">
        <input type="checkbox" ${variableMenu?'checked':''} onchange="toggleVariableMenu()"/> 🔀 תפריט משתנה</label>
      <span style="font-size:0.72rem;color:#777;">כמה אופציות לארוחה — המתאמן בוחר אחת ביום</span>
      ${_mergeUndo ? `<button class="btn-sm btn-outline" style="margin-inline-start:auto;font-size:0.72rem;border-color:rgba(248,113,113,0.5);color:#f87171;" onclick="undoMerge()">↩ בטל איחוד</button>` : ''}
      ${(() => { const ks = mergeableKinds(); if (!ks.length) return '';
        const lbl = k => (MEAL_KINDS.find(x => x[0] === k) || [, k])[1];
        return `<span style="margin-inline-start:auto;display:flex;align-items:center;gap:6px;"><select id="merge-kind-sel" style="padding:4px 8px;background:rgba(255,255,255,0.06);border:1px solid rgba(255,215,0,0.4);border-radius:6px;color:#fff;font-family:'Heebo',sans-serif;font-size:0.72rem;cursor:pointer;">${ks.map(k => `<option value="${k}">${lbl(k)}</option>`).join('')}</select><button class="btn-sm btn-outline" style="font-size:0.72rem;border-color:rgba(255,215,0,0.5);color:var(--gold);" title="מאחד את האופציות של סוג הארוחה שנבחר בלבד" onclick="autoMergeOptions(document.getElementById('merge-kind-sel').value)">🔀 אחד אופציות</button></span>`; })()}
      <button class="btn-sm btn-outline" style="${canAutoMerge() ? '' : 'margin-inline-start:auto;'}font-size:0.72rem;border-color:rgba(255,215,0,0.4);color:var(--gold);" onclick="openFoodAdd('')">➕ מוצר למאגר שלי</button>
    </div>`;
    el.innerHTML = macroBar + vmSwitch + nutritionPlan.map((meal,mi)=>`
      <div class="meal-block${collapsedMeals.has(mi)?' meal-collapsed':''}">
        <div class="meal-block-head">
          <button class="block-toggle" onclick="toggleMealCollapse(${mi})" title="הצג/הסתר ארוחה">▼</button>
          <input value="${esc(meal.meal)}" oninput="nutritionPlan[${mi}].meal=this.value;nutriTouched()" placeholder="שם ארוחה"/>
          <select onchange="nutritionPlan[${mi}].meal_type=this.value;nutriTouched();renderNutritionEditor()" title="סוג הארוחה — לפיו מתבצע איחוד האופציות, כדי שבוקר לא יתמזג עם צהריים" style="padding:4px 6px;background:rgba(255,255,255,0.06);border:1px solid rgba(255,215,0,0.28);border-radius:6px;color:#fff;font-family:'Heebo',sans-serif;font-size:0.72rem;cursor:pointer;flex-shrink:0;">
            <option value="" ${!mealKind(meal) ? 'selected' : ''}>סוג ארוחה…</option>
            ${MEAL_KINDS.map(([v,l]) => `<option value="${v}" ${mealKind(meal)===v?'selected':''}>${l}</option>`).join('')}
          </select>
          <select onchange="nutritionPlan[${mi}].day_type=this.value;nutriTouched()" title="סוג יום — נקבע איזה יום הארוחה מוצגת למתאמן" style="padding:4px 6px;background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.14);border-radius:6px;color:#fff;font-family:'Heebo',sans-serif;font-size:0.72rem;cursor:pointer;flex-shrink:0;">
            ${[['any','כל יום'],['training','🏋️ יום אימון'],['rest','😴 יום מנוחה'],['target','🎯 שריר מטרה']].map(([v,l])=>`<option value="${v}" ${(meal.day_type||'any')===v?'selected':''}>${l}</option>`).join('')}
          </select>
          <div style="display:flex;gap:5px;">
            ${mi < nutritionPlan.length - 1 ? `<button class="btn-sm btn-outline" style="padding:4px 9px;font-size:0.75rem;border-color:rgba(255,215,0,0.45);color:var(--gold);" title="מזג את הארוחה הבאה לכאן כאופציה — המתאמן יבחר אחת" onclick="mergeMealDown(${mi})">🔗 מזג כאופציה</button>` : ''}
            ${(meal.variants||[]).length ? `<button class="btn-sm btn-outline" style="padding:4px 9px;font-size:0.75rem;border-color:rgba(248,113,113,0.45);color:#f87171;" title="מפצל את האופציות בחזרה לארוחות נפרדות" onclick="splitMealOptions(${mi})">⤴ פצל אופציות</button>` : ''}
            <button class="btn-sm btn-outline" style="padding:4px 9px;font-size:0.75rem;" onclick="copyMeal(${mi})">📋 העתק ארוחה</button>
            <button class="btn-sm btn-red" onclick="removeMeal(${mi})">הסר ארוחה</button>
          </div>
        </div>
        <div class="meal-body">
          <div class="nutri-header"><span>מזון</span><span>כמות</span><span>קל׳</span><span>חלבון</span><span>פחמימה</span><span>שומן</span><span></span></div>
          <div>${(meal.items||[]).map((item,ii)=>itemRow(mi,ii,item)).join('')}</div>
          <button class="add-link" onclick="addItem(${mi})">+ הוסף מזון</button>
          ${variableMenu ? variantBlock(mi, meal) : ''}
          ${(meal.items||[]).length ? `
          <div class="meal-alts">
            <div style="font-size:0.78rem;font-weight:700;color:#60b4ff;margin-bottom:8px;">חלופות לארוחה זו:</div>
            ${renderChipsRow(mi,'protein','חלבון')}
            ${renderChipsRow(mi,'carbs','פחמימה')}
            ${renderChipsRow(mi,'fat','שומן')}
          </div>` : ''}
        </div>
      </div>`).join('');
  }
  function itemRow(mi, ii, item) {
    const exp=item._exp||false, unitName=item._unit||'גרם', qty=item._qty!=null?item._qty:(unitName==='גרם'?100:1);
    const units=getUnitsForFood(item.food), selUnit=units.find(u=>u.name===unitName)||units[0];
    const totalG=selUnit?Math.round(qty*selUnit.grams*10)/10:qty;
    const altOpen=item._altOpen||false, alts=item.alternatives||[];
    const unitPicker=exp?`
      <div style="background:rgba(255,107,0,0.06);border:1px solid rgba(255,107,0,0.2);border-radius:8px;padding:8px 12px;margin-top:4px;">
        <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
          <span style="font-size:0.8rem;color:var(--muted);">מידה:</span>
          <select onchange="setItemUnit(${mi},${ii},this.value)" style="padding:5px 8px;background:rgba(255,255,255,0.07);border:1px solid rgba(255,255,255,0.14);border-radius:6px;color:#fff;font-family:'Heebo',sans-serif;font-size:0.82rem;outline:none;cursor:pointer;max-width:200px;">
            ${units.map(u=>`<option value="${esc(u.name)}" ${u.name===unitName?'selected':''}>${esc(u.name)}${u.grams!==1?' ('+u.grams+'g)':''}</option>`).join('')}
          </select>
          <span style="font-size:0.8rem;color:var(--muted);">×</span>
          <input type="number" min="0.1" step="0.1" value="${qty}" style="width:72px;padding:5px 8px;background:rgba(255,255,255,0.07);border:1px solid rgba(255,255,255,0.14);border-radius:6px;color:#fff;font-family:'Heebo',sans-serif;font-size:0.82rem;text-align:center;outline:none;" oninput="setItemQty(${mi},${ii},+this.value)"/>
          <span style="font-size:0.82rem;color:var(--orange);font-weight:700;">= ${totalG}g</span>
        </div>
      </div>`:'' ;
    const altPanel=altOpen?`
      <div style="background:rgba(96,180,255,0.04);border:1px solid rgba(96,180,255,0.2);border-radius:8px;padding:10px 12px;margin-top:5px;">
        <div style="font-size:0.75rem;color:#60b4ff;font-weight:700;margin-bottom:8px;">🔄 חלופות לפריט זה:</div>
        ${alts.length?alts.map((a,ai)=>{
          const _af=findFood(a.name)||(a.food_id?allFoodItems.find(f=>f.id===a.food_id):null);
          const _eqG=(_af&&_af.calories&&item.calories)?Math.round(item.calories/_af.calories*100):null;
          const _qtyStr=_eqG?formatChipQty(a.name,item.calories)||(_eqG+'g'):null;
          /* register swap params in key-map so onclick is always safe */
          const _sk='sb'+(++_swapBtnSeq);
          _swapBtnMap[_sk]={mi,ii,afId:_af?_af.id:0,afName:a.name,eqG:_eqG||0};
          return `<div style="display:flex;align-items:center;gap:8px;margin-bottom:5px;padding:6px 10px;background:rgba(255,255,255,0.03);border-radius:8px;border:1px solid rgba(255,255,255,0.05);">
            <span style="font-size:0.82rem;flex:1;color:#ccc;">${esc(a.name)}</span>
            ${_qtyStr?`<span style="font-size:0.75rem;color:var(--orange);font-weight:700;">${_qtyStr}</span>`:'<span style="font-size:0.72rem;color:#555;">?</span>'}
            ${_eqG?`<button onclick="showSwapPreviewKey('${_sk}')" style="padding:3px 10px;background:rgba(255,107,0,0.15);border:1px solid rgba(255,107,0,0.4);border-radius:6px;color:var(--orange);cursor:pointer;font-size:0.75rem;font-weight:700;font-family:'Heebo',sans-serif;white-space:nowrap;">החלף ↙</button>`:''}
            <button onclick="removeAlt(${mi},${ii},${ai})" style="padding:2px 7px;background:rgba(255,70,70,0.1);border:1px solid rgba(255,70,70,0.3);border-radius:4px;color:#ff7070;cursor:pointer;font-size:0.7rem;">✕</button>
          </div>`;
        }).join(''):'<div style="color:#555;font-size:0.78rem;margin-bottom:8px;">אין חלופות עדיין — חפש מאכל מהמאגר</div>'}
        <div style="position:relative;margin-top:6px;">
          <input type="text" id="alt-inp-${mi}-${ii}" placeholder="הוסף חלופה — חפש מאכל..." autocomplete="off"
            style="width:100%;padding:7px 10px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.12);border-radius:6px;color:#fff;font-family:'Heebo',sans-serif;font-size:0.8rem;outline:none;"
            oninput="showAltSuggCoach(this,${mi},${ii})"
            onfocus="showAltSuggCoach(this,${mi},${ii})"
            onblur="setTimeout(hideAltSuggCoach,160)"/>
          <div id="alt-sugg-${mi}-${ii}" style="display:none;position:absolute;top:calc(100% + 2px);right:0;left:0;background:#1e1e1e;border:1px solid rgba(96,180,255,0.3);border-radius:8px;z-index:700;overflow:hidden;box-shadow:0 6px 20px rgba(0,0,0,0.7);max-height:340px;overflow-y:auto;"></div>
        </div>
      </div>`:'' ;
    return `<div style="margin-bottom:6px;">
      <div class="item-row" id="item-${mi}-${ii}">
        <div style="display:flex;align-items:center;gap:3px;min-width:0;">
          <input value="${esc(item.food)}" oninput="nutritionPlan[${mi}].items[${ii}].food=this.value;showFoodSuggCoach(this,${mi},${ii});nutriTouched()" onblur="setTimeout(hideFoodSuggCoach,160)" autocomplete="off" placeholder="מזון" style="flex:1;min-width:0;padding:6px 8px;background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.08);border-radius:6px;color:#fff;font-family:'Heebo',sans-serif;font-size:0.8rem;outline:none;"/>
          <button onclick="toggleItemExpand(${mi},${ii})" style="padding:3px 7px;background:${exp?'rgba(255,107,0,0.2)':'rgba(255,255,255,0.04)'};border:1px solid ${exp?'rgba(255,107,0,0.45)':'rgba(255,255,255,0.1)'};border-radius:5px;color:${exp?'var(--orange)':'#666'};cursor:pointer;font-size:0.65rem;flex-shrink:0;">${exp?'▲':'▼'}</button>
        </div>
        <div class="mi-cell"><label>כמות</label><input value="${esc(item.quantity)}" oninput="onQuantityInput(${mi},${ii},this.value)" placeholder="כמות"/></div>
        <div class="mi-cell"><label>קלוריות</label><input value="${item.calories||''}" oninput="nutritionPlan[${mi}].items[${ii}].calories=+this.value;nutriTouched()" placeholder="קל׳" type="number"/></div>
        <div class="mi-cell"><label>חלבון</label><input value="${item.protein||''}"  oninput="nutritionPlan[${mi}].items[${ii}].protein=+this.value;nutriTouched()"  placeholder="P"   type="number"/></div>
        <div class="mi-cell"><label>פחמימה</label><input value="${item.carbs||''}"    oninput="nutritionPlan[${mi}].items[${ii}].carbs=+this.value;nutriTouched()"    placeholder="C"   type="number"/></div>
        <div class="mi-cell"><label>שומן</label><input value="${item.fat||''}"      oninput="nutritionPlan[${mi}].items[${ii}].fat=+this.value;nutriTouched()"      placeholder="F"   type="number"/></div>
        <button onclick="toggleItemAlt(${mi},${ii})" style="padding:3px 7px;background:${altOpen||alts.length?'rgba(96,180,255,0.12)':'rgba(255,255,255,0.04)'};border:1px solid ${altOpen||alts.length?'rgba(96,180,255,0.4)':'rgba(255,255,255,0.1)'};border-radius:5px;color:${altOpen||alts.length?'#60b4ff':'#555'};cursor:pointer;font-size:0.65rem;flex-shrink:0;" title="הוסף חלופות">🔄${alts.length?' '+alts.length:''}</button>
        <button class="btn-sm btn-red" onclick="removeItem(${mi},${ii})">✕</button>
      </div>
      ${unitPicker}${altPanel}
    </div>`;
  }
  function toggleMealCollapse(mi) { collapsedMeals.has(mi)?collapsedMeals.delete(mi):collapsedMeals.add(mi); renderNutritionEditor(); }
  /* ═══ 🔀 תפריט משתנה — אופציות לארוחה ═══
     ארוחה יכולה לשאת כמה גרסאות, והמתאמן בוחר אחת ביום.

     המבנה נשמר תואם לאחור בכוונה: הבסיס נשאר ב-items כפי שהיה,
     והגרסאות הנוספות יושבות ב-variants. תפריט קיים בלי variants
     נטען ומוצג בדיוק כמו קודם, אצל המאמן ואצל המתאמן.

     ההמרה מתאימה לפי תפקיד הפריט ולא לפי קלוריות: מקור חלבון
     מוחלף כך שייתן את אותו חלבון. אי אפשר להתאים את שלושת המאקרו
     בהחלפת מזון אחד, ולכן מה שנשמר הוא מה שהפריט נועד לספק —
     והפער בקלוריות מוצג במפורש במקום להיעלם. */

  /* תפקיד הפריט. נשמר על הפריט כשהמאמן קובע ידנית; אחרת נגזר
     מהמאקרו, באותה לוגיקה של החלופות. */
  const itemRole = it => it.role || dominantMacro(it);
  const ROLE_LABEL = { protein: 'חלבון', carbs: 'פחמימה', fat: 'שומן' };

  const macroSum = items => (items || []).reduce((a, i) => ({
    calories: a.calories + (+i.calories || 0), protein: a.protein + (+i.protein || 0),
    carbs: a.carbs + (+i.carbs || 0), fat: a.fat + (+i.fat || 0),
  }), { calories: 0, protein: 0, carbs: 0, fat: 0 });

  /* כמה גרם מהמזון החדש נדרשים כדי לספק אותה כמות מהמאקרו המוביל.
     מחזיר null כשאין במזון את המאקרו הזה — למשל "אורז" כמקור חלבון,
     שהיה מייצר כמות אבסורדית. */
  /* סף צפיפות מינימלי למאקרו, כדי שמזון ייחשב מקור אמיתי שלו.
     תקרת גרמים לבדה לא הספיקה: אורז מכיל 2.7 גרם חלבון ל-100, ולכן
     2,296 גרם ממנו "נותנים" 62 גרם חלבון — מתחת לכל תקרה סבירה
     ועדיין תוצאה אבסורדית. אותם ספים משמשים את רשימת ההשלמה, כך
     שכל בחירה משם מצליחה. */
  const ROLE_MIN = { protein: 8, carbs: 15, fat: 8 };

  function convertByRole(targetGrams100, sourceItem, newFood, role) {
    const per100 = +newFood[role] || 0;
    if (per100 < (ROLE_MIN[role] || 1)) return null;
    const need = +sourceItem[role] || 0;
    if (need <= 0) return null;
    const grams = Math.round(need / per100 * 100);
    if (!isFinite(grams) || grams <= 0 || grams > 1500) return null;   // שפיות
    const f = grams / 100;
    return {
      food: newFood.name, quantity: `${grams} גרם`, role,
      calories: Math.round(newFood.calories * f),
      protein: Math.round(newFood.protein * f * 10) / 10,
      carbs: Math.round(newFood.carbs * f * 10) / 10,
      fat: Math.round(newFood.fat * f * 10) / 10,
    };
  }

  function variantsOf(m) { return m.variants || []; }
  function optionCount(m) { return 1 + variantsOf(m).length; }

  /* תפריטים ותיקים נבנו כארוחות נפרדות בשם "ארוחת בוקר — אופציה 2",
     כי לא הייתה אז אפשרות לאופציות. למתאמן הן נראות כשלוש ארוחות
     שצריך לאכול, במקום בחירה אחת מתוך שלוש. המיזוג כאן הופך אותן
     למבנה הנכון בלי להקליד מחדש — במקביל ל-🔗 של הסופר-סט. */
  const OPT_RE = /^(.*?)[\s]*[—\-–:(]+[\s]*אופצי[יה]?ה[\s]*(\d+)[\s)]*$/;
  /* ארוחה עם אופציות נספרה עד כה לפי items בלבד — כלומר רק אופציה 1,
     ושאר האופציות לא השפיעו על היעדים כלל. מכיוון שהמתאמן אוכל אופציה
     אחת ביום ולא את כולן, הערך הנכון לייצוג הארוחה הוא הממוצע על פני
     האופציות: כך היעד היומי משקף את מה שייצא בפועל, בלי תלות במה
     שנבחר. אופציות שנבנו נכון קרובות זו לזו ממילא, והממוצע פשוט
     מונע הטיה לטובת האופציה הראשונה. */
  function mealAvg(m, f) {
    const one = arr => (arr || []).reduce((a, i) => a + (+i[f] || 0), 0);
    const opts = [m.items || [], ...((m.variants || []).map(v => v.items || []))];
    return opts.reduce((a, it) => a + one(it), 0) / opts.length;
  }
  function planSum(f) {
    return Math.round(nutritionPlan.reduce((s, m) => s + mealAvg(m, f), 0));
  }

  /* איחוד לפי שם הבסיס לבדו שביר: "בוקר" ו"ארוחת בוקר" נחשבו שונים,
     ובכיוון השני שתי ארוחות שונות שקיבלו במקרה אותו שם היו מתמזגות.
     סוג הארוחה הוא שדה מפורש שהמאמן קובע, וההחלטה נשענת עליו.
     הניחוש מהשם קיים כדי שתפריטים ותיקים יעבדו בלי לתייג ידנית —
     אבל בחירה מפורשת תמיד גוברת עליו. */
  const MEAL_KINDS = [
    ['breakfast', '🌅 בוקר'], ['snack', '🥤 ביניים'], ['pre', '⚡ לפני אימון'],
    ['lunch', '🍽 צהריים'], ['post', '💪 אחרי אימון'], ['dinner', '🌙 ערב'],
    ['night', '😴 לילה'],
  ];
  function guessMealKind(name) {
    const t = String(name || '');
    if (/לפני\s*ה?אימון|pre[\s-]?workout/i.test(t)) return 'pre';
    if (/אחרי\s*ה?אימון|post[\s-]?workout/i.test(t)) return 'post';
    if (/לילה|לפני\s*ה?שינה/.test(t)) return 'night';
    if (/בוקר/.test(t)) return 'breakfast';
    if (/צהר/.test(t)) return 'lunch';
    if (/ערב/.test(t)) return 'dinner';
    if (/ביניים|נשנוש/.test(t)) return 'snack';
    return '';
  }
  const mealKind = m => m.meal_type || guessMealKind(m.meal);

  function mealBaseName(name) {
    const m = String(name || '').match(OPT_RE);
    return m ? m[1].trim() : String(name || '').trim();
  }
  function mealOptNum(name) {
    const m = String(name || '').match(OPT_RE);
    return m ? parseInt(m[2]) : null;
  }

  /* ממזג את הארוחה הבאה לתוך הנוכחית כאופציה נוספת. */
  function mergeMealDown(mi) {
    if (!requireEdit()) return;
    const a = nutritionPlan[mi], b = nutritionPlan[mi + 1];
    if (!a || !b) return;
    /* סוג היום נשמר על הארוחה ולא על האופציה. מיזוג של "יום אימון"
       עם "יום מנוחה" היה מוחק את ההבחנה בשקט, ולכן הוא נחסם. */
    if ((a.day_type || 'any') !== (b.day_type || 'any')) {
      toast('אי אפשר למזג ארוחות עם סוג יום שונה', 'err'); return;
    }
    /* ההגנה המרכזית: בוקר לא יתמזג עם צהריים גם בלחיצה ידנית. */
    const ka = mealKind(a), kb = mealKind(b);
    if (ka && kb && ka !== kb) {
      const lbl = k => (MEAL_KINDS.find(x => x[0] === k) || [, k])[1];
      toast(`אי אפשר למזג ${lbl(ka)} עם ${lbl(kb)} — סוג ארוחה שונה`, 'err'); return;
    }
    a.variants = a.variants || [];
    a.variants.push({
      label: 'אופציה ' + (a.variants.length + 2),
      items: JSON.parse(JSON.stringify(b.items || [])).map(i => ({ ...i, role: itemRole(i) })),
    });
    /* גם האופציות של הארוחה הנבלעת עוברות, אחרת מיזוג שני היה מוחק אותן */
    for (const v of (b.variants || [])) {
      a.variants.push({ label: 'אופציה ' + (a.variants.length + 2), items: v.items || [] });
    }
    a.meal = mealBaseName(a.meal);
    nutritionPlan.splice(mi + 1, 1);
    renderNutritionEditor(); nutriTouched();
    toast('מוזג — ' + (a.variants.length + 1) + ' אופציות ב' + a.meal, 'ok');
  }

  /* הכפתור מוצג רק כשיש באמת מה לאחד — שתי ארוחות מאותו סוג ואותו
     יום, או שמות "אופציה N" חוזרים. */
  /* אילו סוגי ארוחה יש להם שתי אופציות או יותר — כדי שהבורר יציג
     רק מה שבאמת ניתן לאחד. */
  function mergeableKinds() {
    const cnt = new Map();
    for (const m of nutritionPlan) {
      if (mealOptNum(m.meal) === null) continue;
      const k = mealKind(m) || mealBaseName(m.meal);
      const key = k + '|' + (m.day_type || 'any');
      cnt.set(key, (cnt.get(key) || 0) + 1);
    }
    const out = [];
    for (const [key, n] of cnt) if (n > 1) {
      const k = key.split('|')[0];
      if (!out.includes(k)) out.push(k);
    }
    return out;
  }

  function canAutoMerge() {
    const seen = new Map();
    for (const m of nutritionPlan) {
      if (mealOptNum(m.meal) === null) continue;
      const k = (mealKind(m) || mealBaseName(m.meal)) + '|' + (m.day_type || 'any');
      seen.set(k, (seen.get(k) || 0) + 1);
      if (seen.get(k) > 1) return true;
    }
    return false;
  }

  /* סורק את כל התפריט ומאחד לפי סוג הארוחה. */
  /* התפריט נשמר אוטומטית ואין היסטוריית גרסאות — לכן לפני איחוד
     נשמר עותק, וכפתור ביטול מוצג עד שהמאמן עוזב את המתאמן. */
  let _mergeUndo = null;
  function undoMerge() {
    if (!_mergeUndo) return;
    nutritionPlan = _mergeUndo;
    _mergeUndo = null;
    renderNutritionEditor(); nutriTouched();
    toast('האיחוד בוטל — התפריט הוחזר', 'ok');
  }

  /* הפעולה ההפוכה לאיחוד. מיזוג אינו מוחק מזון — הוא מעביר אותו
     ל-variants — ולכן אפשר תמיד לפרוש אותו בחזרה לארוחות נפרדות.
     זו גם דרך השחזור אם אוחדו ארוחות שלא היו אמורות להתאחד. */
  function splitMealOptions(mi) {
    if (!requireEdit()) return;
    const m = nutritionPlan[mi];
    const vars = m && m.variants || [];
    if (!vars.length) { toast('אין אופציות לפצל בארוחה הזו', 'err'); return; }
    if (!confirm(`הארוחה "${m.meal}" תפוצל ל-${vars.length + 1} ארוחות נפרדות.` +
                 String.fromCharCode(10,10) + 'כל אופציה תהפוך לארוחה בפני עצמה. להמשיך?')) return;
    const base = mealBaseName(m.meal);
    const made = [Object.assign({}, m, {
      meal: base + ' — אופציה 1', variants: undefined })];
    delete made[0].variants;
    vars.forEach((v, k) => {
      made.push({
        meal: base + ' — אופציה ' + (k + 2),
        meal_type: m.meal_type || undefined,
        day_type: m.day_type || 'any',
        items: JSON.parse(JSON.stringify(v.items || [])),
      });
    });
    nutritionPlan.splice(mi, 1, ...made);
    renderNutritionEditor(); nutriTouched();
    toast(made.length + ' ארוחות נפרדות ✓', 'ok');
  }

  /* המאמן בוחר במפורש איזה סוג ארוחה מאוחד. סריקה גורפת של כל
     התפריט הייתה מאחדת גם מה שלא התכוון, ולכן היעד נבחר ידנית. */
  function autoMergeOptions(onlyKind) {
    if (!requireEdit()) return;
    const groups = new Map();
    nutritionPlan.forEach((m, i) => {
      /* סוג הארוחה קודם לשם. כשהוא ידוע — נבחר או נוחש — הוא המפתח,
         ולכן "בוקר" ו"ארוחת בוקר" מתאחדים ובוקר לעולם לא מתמזג עם
         צהריים. בלי סוג נופלים לשם הבסיס כמקודם. */
      /* רק שם עם "אופציה N" מסמן כוונה למזג. הסוג (גם המנוחש)
         משמש לקיבוץ ולחסימת ערבוב — אך לא כטריגר, אחרת שתי ארוחות
         ביניים נפרדות היו מתמזגות לבחירה אחת. */
      if (mealOptNum(m.meal) === null) return;
      if (onlyKind && mealKind(m) !== onlyKind) return;   // רק הסוג שנבחר
      const kind = mealKind(m);
      const key = (kind || mealBaseName(m.meal)) + '|' + (m.day_type || 'any');
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(i);
    });
    const merges = [...groups.values()].filter(g => g.length > 1);
    if (!merges.length) {
      toast('לא נמצאו ארוחות בשם "… אופציה 2" למיזוג', 'err'); return;
    }
    const total = merges.reduce((a, g) => a + g.length, 0);
    if (!confirm(merges.length + ' ארוחות ימוזגו מ-' + total + ' שורות.' +
                 String.fromCharCode(10,10) + 'המתאמן יראה ארוחה אחת ויבחר אופציה. להמשיך?')) return;

    /* בונים תפריט חדש במקום למחוק תוך כדי מעבר — מחיקה באמצע לולאה
       מזיזה את כל האינדקסים ומוחקת את הארוחה הלא נכונה. */
    _mergeUndo = JSON.parse(JSON.stringify(nutritionPlan));
    const consumed = new Set();
    const out = [];
    for (let i = 0; i < nutritionPlan.length; i++) {
      if (consumed.has(i)) continue;
      const m = nutritionPlan[i];
      const kind = mealKind(m);
      const key = (kind || mealBaseName(m.meal)) + '|' + (m.day_type || 'any');
      const group = groups.get(key);
      if (mealOptNum(m.meal) === null || (onlyKind && mealKind(m) !== onlyKind) ||
          !group || group.length < 2) { out.push(m); continue; }
      /* ארוחות ללא "אופציה N" בשם ממוינות לפי סדר הופעתן, אחרת
         mealOptNum מחזיר null והמיון היה הופך לא צפוי. */
      const sorted = [...group].sort((x, y) =>
        (mealOptNum(nutritionPlan[x].meal) ?? x) - (mealOptNum(nutritionPlan[y].meal) ?? y));
      const base = nutritionPlan[sorted[0]];
      base.meal = mealBaseName(base.meal);
      base.variants = base.variants || [];
      for (const idx of sorted.slice(1)) {
        const other = nutritionPlan[idx];
        base.variants.push({
          label: 'אופציה ' + (base.variants.length + 2),
          items: JSON.parse(JSON.stringify(other.items || [])).map(it => ({ ...it, role: itemRole(it) })),
        });
        for (const v of (other.variants || []))
          base.variants.push({ label: 'אופציה ' + (base.variants.length + 2), items: v.items || [] });
      }
      group.forEach(idx => consumed.add(idx));
      out.push(base);
    }
    nutritionPlan = out;
    renderNutritionEditor(); nutriTouched();
    toast(merges.length + ' ארוחות אוחדו — אפשר לבטל בכפתור ↩', 'ok');
  }

  function addVariant(mi) {
    const m = nutritionPlan[mi];
    m.variants = m.variants || [];
    /* הגרסה החדשה מתחילה כהעתק של הבסיס — כך המאמן מחליף רק את מה
       שהוא רוצה, במקום להקליד ארוחה שלמה מאפס. */
    m.variants.push({
      label: `אופציה ${optionCount(m) + 1}`,
      items: JSON.parse(JSON.stringify(m.items || [])).map(i => ({ ...i, role: itemRole(i) })),
    });
    renderNutritionEditor(); nutriTouched();
  }
  function removeVariant(mi, vi) {
    nutritionPlan[mi].variants.splice(vi, 1);
    if (!nutritionPlan[mi].variants.length) delete nutritionPlan[mi].variants;
    renderNutritionEditor(); nutriTouched();
  }

  /* החלפת מזון בתוך גרסה — הכמות מחושבת לפי תפקיד הפריט */
  function swapVariantItem(mi, vi, ii, foodName) {
    const m = nutritionPlan[mi];
    const v = m.variants[vi];
    const it = v.items[ii];
    const base = (m.items || [])[ii] || it;
    const role = itemRole(base);
    const name = String(foodName || '').trim();
    if (!name) return;

    const fd = findFood(name);
    const conv = fd ? convertByRole(null, base, fd, role) : null;
    if (conv) { v.items[ii] = conv; renderNutritionEditor(); nutriTouched(); return; }

    /* המזון לא נמצא במאגר, או שאין בו את המאקרו הנדרש. קודם הקלט
       פשוט נזרק והשדה חזר לערכו הישן — מה שנראה כאילו הפיצ'ר לא
       שומר. עכשיו השם נשמר והמאקרו מתאפס לעריכה ידנית, כדי שאפשר
       יהיה להשתמש גם במזון שאינו במאגר. */
    v.items[ii] = { ...it, food: name, role, quantity: '', calories: 0, protein: 0, carbs: 0, fat: 0, manual: true };
    renderNutritionEditor(); nutriTouched();
    /* מזון שאינו במאגר — מציעים להוסיף אותו פעם אחת, ואז הוא זמין
       בכל תפריט עתידי במקום למלא אותו ידנית שוב ושוב. */
    if (!fd && confirm(`"${name}" אינו במאגר.

להוסיף אותו למאגר שלך עם ערכים תזונתיים?
כך הוא יהיה זמין בכל תפריט.`)) {
      openFoodAdd(name);
      return;
    }
    toast(fd ? `ל"${fd.name}" אין ${ROLE_LABEL[role]} — מלא כמות ידנית`
             : 'מלא כמות ומאקרו ידנית', 'err');
  }

  /* רשימת מקורות לפי מאקרו, להשלמה אוטומטית בשדה הגרסה.
     מסוננת למזונות שבאמת מספקים את המאקרו — כך שכל בחירה מהרשימה
     מצליחה בהמרה, ואי אפשר לבחור "אורז" כמקור חלבון. */
  const _roleListCache = {};
  function roleDatalist(role) {
    if (_roleListCache[role]) return _roleListCache[role];
    const min = ROLE_MIN[role] || 1;   // אותו סף של ההמרה, כדי שכל בחירה מהרשימה תצליח
    const opts = (allFoodItems || [])
      .filter(f => (+f[role] || 0) >= min)
      .sort((a, b) => (+b[role] || 0) - (+a[role] || 0))
      .slice(0, 300)
      .map(f => `<option value="${esc(f.name)}"></option>`).join('');
    _roleListCache[role] = `<datalist id="rl-${role}">${opts}</datalist>`;
    return _roleListCache[role];
  }

  /* סוגר את פער הקלוריות מול הבסיס ע"י כיוון מקור הפחמימה.
     נבחרה פחמימה ולא חלבון או שומן: היא הזולה ביותר מבחינה
     תזונתית לשינוי, ולא פוגעת ביעד החלבון שהוא העיקר. */
  function balanceVariant(mi, vi) {
    const m = nutritionPlan[mi];
    const v = m.variants[vi];
    const base = macroSum(m.items), cur = macroSum(v.items);
    const gap = base.calories - cur.calories;
    if (Math.abs(gap) < 5) { toast('האופציה כבר מאוזנת', 'ok'); return; }
    /* סדר עדיפות לאיזון: פחמימה, ואם אין — שומן. חלבון אחרון, כי
       הוא היעד שהכי חשוב לשמר. ארוחה בלי פחמימה היא תקינה לגמרי
       (ערב, לפני שינה), ולכן אין להיתקע בלעדיה. */
    const idx = ['carbs', 'fat', 'protein']
      .map(r => v.items.findIndex(i => itemRole(i) === r))
      .find(i => i >= 0);
    if (idx === undefined) { toast('אין פריט שניתן לאזן דרכו', 'err'); return; }
    const it = v.items[idx];
    const fd = findFood(it.food);
    if (!fd || !fd.calories) { toast('המזון לא נמצא במאגר', 'err'); return; }
    const curG = parseFloat(String(it.quantity).replace(/[^\d.]/g, '')) || 0;
    const newG = Math.round(curG + gap / fd.calories * 100);
    if (newG <= 0) { toast('לא ניתן לאזן — הפער גדול מדי', 'err'); return; }
    const f = newG / 100;
    v.items[idx] = { ...it, quantity: `${newG} גרם`,
      calories: Math.round(fd.calories * f), protein: Math.round(fd.protein * f * 10) / 10,
      carbs: Math.round(fd.carbs * f * 10) / 10, fat: Math.round(fd.fat * f * 10) / 10 };
    renderNutritionEditor(); nutriTouched();
    toast('האופציה אוזנה ✓', 'ok');
  }

  /* הסוויץ' הגלובלי. נגזר מהנתונים ולא נשמר בנפרד: אם קיימת ולו
     ארוחה אחת עם אופציות — הוא דלוק, וכיבויו לא מוחק אותן. */
  /* שני מקורות למצב הסוויץ': סימון ידני, ונוכחות אופציות בנתונים.
     חישוב מהנתונים בלבד היה מכבה את הסימון הידני ברינדור הבא —
     כי בזמן הסימון עדיין אין אופציות — ולכן אי אפשר היה להדליק אותו
     בכלל. הידני נשמר בנפרד, וההצגה היא איחוד של השניים. */
  let variableMenu = false, _vmManual = false;
  function syncVariableMenu() {
    variableMenu = _vmManual || nutritionPlan.some(m => (m.variants || []).length);
  }
  function toggleVariableMenu() {
    _vmManual = !variableMenu;
    renderNutritionEditor();
  }

  function variantBlock(mi, meal) {
    const vars = variantsOf(meal);
    const base = macroSum(meal.items);
    const rows = vars.map((v, vi) => {
      const cur = macroSum(v.items);
      const gap = Math.round(cur.calories - base.calories);
      const pGap = Math.round((cur.protein - base.protein) * 10) / 10;
      return `<div style="border:1px solid rgba(96,180,255,0.22);border-radius:10px;padding:10px;margin-top:7px;background:rgba(96,180,255,0.03);">
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:7px;flex-wrap:wrap;">
          <input value="${esc(v.label || '')}" oninput="nutritionPlan[${mi}].variants[${vi}].label=this.value;nutriTouched()"
            style="flex:1;min-width:90px;padding:4px 8px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.12);border-radius:6px;color:#7ec8ff;font-family:'Heebo';font-size:0.78rem;font-weight:700;"/>
          <span style="font-size:0.72rem;color:#888;">${Math.round(cur.calories)} קל׳ · ${Math.round(cur.protein)}ח</span>
          ${Math.abs(gap) >= 5 ? `<span style="font-size:0.7rem;color:#f0a24b;font-weight:700;">${gap > 0 ? '+' : ''}${gap} קל׳</span>
            <button class="btn-sm btn-outline" style="font-size:0.64rem;padding:2px 8px;" onclick="balanceVariant(${mi},${vi})">אזן</button>` : ''}
          ${Math.abs(pGap) >= 2 ? `<span style="font-size:0.7rem;color:#f87171;font-weight:700;">${pGap > 0 ? '+' : ''}${pGap}ח</span>` : ''}
          ${fatExcess(meal, v) > 0.5 ? `<span style="font-size:0.7rem;color:#f0a24b;font-weight:700;">+${fatExcess(meal, v)}ש</span>
            <button class="btn-sm btn-outline" style="font-size:0.64rem;padding:2px 8px;border-color:rgba(240,162,75,0.4);color:#f0a24b;" onclick="trimFat(${mi},${vi})" title="קזז את עודף השומן ממקור השומן בארוחה">🔻 הורד שומן</button>` : ''}
          <button class="btn-sm btn-red" style="font-size:0.64rem;padding:2px 8px;" onclick="removeVariant(${mi},${vi})">✕</button>
        </div>
        ${(v.items || []).map((it, ii) => {
          const role = itemRole((meal.items || [])[ii] || it);
          return `<div style="display:flex;align-items:center;gap:6px;padding:3px 0;flex-wrap:wrap;">
            <span style="font-size:0.62rem;color:#666;min-width:44px;">${ROLE_LABEL[role]}</span>
            <input value="${esc(it.food || '')}" placeholder="מקור ${ROLE_LABEL[role]}" list="rl-${role}"
              onchange="swapVariantItem(${mi},${vi},${ii},this.value)"
              style="flex:2;min-width:100px;padding:4px 8px;background:rgba(255,255,255,0.05);border:1px solid ${it.manual?'rgba(240,162,75,0.5)':'rgba(255,255,255,0.12)'};border-radius:6px;color:#fff;font-family:'Heebo';font-size:0.76rem;"/>
            ${it.manual
              ? `<input value="${esc(it.quantity||'')}" placeholder="כמות"
                   oninput="nutritionPlan[${mi}].variants[${vi}].items[${ii}].quantity=this.value;nutriTouched()"
                   style="width:70px;padding:4px 6px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.12);border-radius:6px;color:#fff;font-family:'Heebo';font-size:0.72rem;"/>
                 <input type="number" value="${it.calories||''}" placeholder="קל׳"
                   oninput="nutritionPlan[${mi}].variants[${vi}].items[${ii}].calories=+this.value;nutriTouched()"
                   style="width:58px;padding:4px 6px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.12);border-radius:6px;color:#fff;font-family:'Heebo';font-size:0.72rem;"/>
                 <input type="number" value="${it[role]||''}" placeholder="${ROLE_LABEL[role]}"
                   oninput="nutritionPlan[${mi}].variants[${vi}].items[${ii}]['${role}']=+this.value;nutriTouched()"
                   style="width:58px;padding:4px 6px;background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.12);border-radius:6px;color:#fff;font-family:'Heebo';font-size:0.72rem;"/>`
              : `<span style="font-size:0.72rem;color:var(--gold);min-width:62px;">${esc(it.quantity || '—')}</span>
                 <span style="font-size:0.68rem;color:#777;">${Math.round(it.calories || 0)}קל׳</span>`}
          </div>`;
        }).join('')}
      </div>`;
    }).join('');

    return `<div style="margin-top:8px;">
      ${vars.length ? roleDatalist('protein') + roleDatalist('carbs') + roleDatalist('fat') : ''}
      ${vars.length ? `<div style="font-size:0.7rem;color:#7ec8ff;font-weight:700;">🔀 ${optionCount(meal)} אופציות — המתאמן יבחר אחת</div>` : ''}
      ${rows}
      ${(meal.items || []).length
        ? `<button class="add-link" style="color:#7ec8ff;" onclick="addVariant(${mi})">+ הוסף אופציה</button>`
        : ''}
    </div>`;
  }

  /* עודף השומן של הגרסה מול הבסיס. מקור חלבון שמן יותר — פרגית
     במקום חזה עוף — מכניס שומן שלא היה, ואת זה מקזזים ממקור השומן
     הנפרד שבארוחה. */
  function fatExcess(m, v) {
    return Math.round((macroSum(v.items).fat - macroSum(m.items).fat) * 10) / 10;
  }

  function trimFat(mi, vi) {
    const m = nutritionPlan[mi], v = m.variants[vi];
    const excess = fatExcess(m, v);
    if (excess <= 0.5) { toast('אין עודף שומן באופציה הזו', 'ok'); return; }

    /* מקזזים ממקור השומן — לא מהחלבון שהוא היעד, ולא מהפחמימה
       שאינה מקור השומן. מדלגים על הפריט שהוחלף עצמו. */
    const idx = v.items.findIndex((i, k) => itemRole(i) === 'fat' && itemRole((m.items || [])[k] || i) === 'fat');
    if (idx < 0) { toast('אין מקור שומן נפרד לקיזוז — הפחת ידנית', 'err'); return; }

    const it = v.items[idx];
    const fd = findFood(it.food);
    if (!fd || !fd.fat) { toast('המזון לא נמצא במאגר', 'err'); return; }

    const curG = parseFloat(String(it.quantity).replace(/[^\d.]/g, '')) || 0;
    const removeG = excess / fd.fat * 100;
    const newG = Math.round(curG - removeG);

    if (newG <= 4) {
      /* הקיזוז גדול ממקור השומן כולו — מסירים אותו לגמרי, וזה
         בדיוק מה שמאמן היה עושה: אין שמן בארוחה עם פרגית. */
      v.items.splice(idx, 1);
      renderNutritionEditor(); nutriTouched();
      toast(`"${it.food}" הוסר — השומן מגיע ממקור החלבון`, 'ok');
      return;
    }
    const f = newG / 100;
    v.items[idx] = { ...it, quantity: `${newG} גרם`,
      calories: Math.round(fd.calories * f), protein: Math.round(fd.protein * f * 10) / 10,
      carbs: Math.round(fd.carbs * f * 10) / 10, fat: Math.round(fd.fat * f * 10) / 10 };
    renderNutritionEditor(); nutriTouched();
    toast(`השומן הופחת ל-${newG} גרם ✓`, 'ok');
  }

  function addMeal()       { nutritionPlan.push({meal:'',items:[]}); renderNutritionEditor(); nutriTouched(); }
  function removeMeal(i)   { nutritionPlan.splice(i,1); renderNutritionEditor(); nutriTouched(); }
  function addItem(mi)     { nutritionPlan[mi].items.push({food:'',quantity:'',calories:0,protein:0,carbs:0,fat:0}); renderNutritionEditor(); nutriTouched(); }
  function removeItem(mi,ii) { nutritionPlan[mi].items.splice(ii,1); renderNutritionEditor(); nutriTouched(); }
  /* ⇊ מסנכרן את סכומי התפריט ליעדי המאקרו בכרטיס הלקוח.
     כשהתפריט נבנה — הערכים שלו הם היעד היומי בפועל, ולכן הם נכתבים
     גם לשדות הכרטיס וגם לבסיס הנתונים (בלי להמתין ל"שמור פרטים"). */
  async function syncMenuToClientTargets(silent) {
    if (!activeEmail || !canEdit) return false;
    const sum = f => planSum(f);
    const t = { target_calories: sum('calories'), target_protein: sum('protein'),
                target_carbs: sum('carbs'),      target_fat: sum('fat') };
    if (!t.target_calories && !t.target_protein) return false;   // תפריט ריק — לא לאפס יעדים קיימים
    const set = (id, v) => { const el = document.getElementById(id); if (el) el.value = v || ''; };
    set('e-cal', t.target_calories); set('e-prot', t.target_protein);
    set('e-carb', t.target_carbs);   set('e-fat', t.target_fat);
    const { error } = await sb.from('clients').update(t).eq('email', activeEmail);
    if (error) { if (!silent) toast('שגיאה בעדכון היעדים: ' + error.message, 'err'); return false; }
    const c = clients.find(x => x.email === activeEmail);
    if (c) Object.assign(c, t);
    refreshNutriTotals();
    if (!silent) toast(`יעדי הכרטיס עודכנו לפי התפריט ✓ (${t.target_calories} קל׳)`, 'ok');
    return true;
  }

  /* ── עריכת תפריט: עדכון חי + שמירה אוטומטית ──
     קודם העריכה עדכנה רק את האובייקט בזיכרון: סרגל המאקרו לא זז, ושום דבר
     לא נשמר עד לחיצה על "שמור תפריט" — ולכן שינויים "לא נקלטו".
     nutriTouched() מרענן את הסרגל בלי לרנדר מחדש (לא מאבד פוקוס) ומתזמן שמירה. */
  let _nutriSaveTimer = null;
  function refreshNutriTotals() {
    const box = document.getElementById('nutri-macro-bar'); if (!box) return;
    const sum = f => planSum(f);
    const TARGET = { calories:'e-cal', protein:'e-prot', carbs:'e-carb', fat:'e-fat' };
    const UNIT   = { calories:'', protein:' ג׳', carbs:' ג׳', fat:' ג׳' };
    box.querySelectorAll('[data-macro]').forEach(row => {
      const k = row.getAttribute('data-macro');
      const val = sum(k), tg = parseInt(document.getElementById(TARGET[k])?.value) || 0;
      const txt = row.querySelector('.macro-val'), fill = row.querySelector('.macro-fill');
      if (txt)  txt.innerHTML = `${val}${UNIT[k]}${tg ? ` <span style="color:#555;">/ ${tg}</span>` : ''}`;
      if (fill) fill.style.width = (tg ? Math.min(100, Math.round(val / tg * 100)) : (val > 0 ? 100 : 0)) + '%';
    });
  }
  /* השמירה המושהית קראה את activeEmail ואת nutritionPlan ברגע שירתה,
     ולא ברגע שנקבעה. מאמן שערך את רוני ופתח מתאמן אחר בתוך 1.2 שניות
     גרם לטיימר לכתוב את התוכנית של רוני על המתאמן החדש — ומבחינת
     המאמן זה נראה כאילו התוכנית "נמחקה".

     כאן נלכדים המייל והתוכנית ברגע העריכה, והשמירה מקבלת אותם
     במפורש. גם אם המסך התחלף בינתיים, מה שנכתב הוא בדיוק מה שהיה
     על המסך כשהמאמן הקליד, ואל המתאמן הנכון. */
  let _nutriPending = null;   // { email, plan } — עריכה שטרם נשמרה

  function nutriTouched() {
    refreshNutriTotals();
    if (!activeEmail || !canEdit) return;
    clearTimeout(_nutriSaveTimer);
    _nutriPending = { email: activeEmail, plan: JSON.parse(JSON.stringify(nutritionPlan)) };
    _nutriSaveTimer = setTimeout(flushNutriSave, 1200);
  }

  /* שומרת מיד את מה שממתין, ומחזירה true גם כשאין מה לשמור.
     נקראת גם מהטיימר וגם לפני מעבר בין מתאמנים. */
  async function flushNutriSave() {
    clearTimeout(_nutriSaveTimer);
    const p = _nutriPending;
    _nutriPending = null;
    if (!p) return true;
    const ok = await saveNutritionFor(p.email, p.plan, true);
    const chip = document.getElementById('nutri-save-chip');
    if (chip && ok !== false) { chip.style.opacity = '1'; setTimeout(() => { chip.style.opacity = '0'; }, 1600); }
    return ok;
  }
  function hasUnsavedNutrition() { return !!_nutriPending; }

  /* שמירה אל מתאמן מפורש. כל מי שקורא לה מוסר את המייל ואת התוכנית,
     ולכן היא אינה תלויה במה שמוצג על המסך ברגע הריצה. */
  async function saveNutritionFor(email, plan, silent) {
    if (silent ? !canEdit : !requireEdit()) return false;
    if (!email) return false;
    /* אצל סגן זו הצעה, לא שמירה. השמירה האוטומטית (silent) מדוכאת
       בכוונה — אחרת כל הקלדה הייתה מייצרת הצעה חדשה ומציפה את הבכיר. */
    if (isDeputyFor(email)) {
      if (silent) return true;
      return proposeChange('nutrition_plan', plan,
        `${(plan || []).length} ארוחות`, false);
    }
    const { error } = await sb.from('nutrition_plans').upsert({client_email:email,plan:plan,updated_at:new Date().toISOString()},{onConflict:'client_email'});
    if (!silent) error ? toast('שגיאה בשמירה','err') : toast('תפריט נשמר ✓','ok');
    return !error;
  }

  /* שמירה ידנית — מה שעל המסך, למתאמן שעל המסך. */
  async function saveNutrition(silent) {
    _nutriPending = null;             // הידנית גוברת על מה שהמתין
    clearTimeout(_nutriSaveTimer);
    return saveNutritionFor(activeEmail, nutritionPlan, silent);
  }

  /* בונה את רשימת התרגילים לפרומפט של ה-AI.
     המאגר גדל ל-1,100+, ושליחת כולו מנפחת את הפרומפט (~9K טוקנים) ומפזרת את
     ה-AI על שרירים לא רלוונטיים. לכן: (1) אם המאמן ציין קבוצות שריר בבקשה —
     שולחים אותן במלואן ואת השאר מקוצצות; (2) בכל מקרה מגבילים לכל קבוצה,
     ומעדיפים תרגילים עם הדגמה + שם עברי (האיכותיים) בראש הרשימה. */
