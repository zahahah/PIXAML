libdir="/vendor"

LIB=libv4a_re.so
LIBNAME=v4a_re
NAME=v4a_re
UUID=90380da3-8536-4744-a6a3-5731970e640f
TYPE=b9bc100c-26cd-42e6-acb6-cad8c3f778de
AUDEFXML="$(find $MODPATH -type f -name *audio*effects*.xml)"

LIB2=libv4a_aidl.so
LIBNAME2=v4a_aidl
NAME2=v4a_standard_aidl
UUID2=90380da3-8536-4744-a6a3-5731970e640f
TYPE2=7261676f-6d75-7369-6364-28e2fd3ac39e

if [ -n "$V4A" ];then
for XML in $AUDEFXML; do
	sed -i "/<libraries>/a\        <library name=\"$LIBNAME\" path=\"$LIB\"\/>" $XML
	sed -i "/<effects>/a\        <effect name=\"$NAME\" library=\"$LIBNAME\" uuid=\"$UUID\"\ type=\"$TYPE\"\/>" $XML
done
fi
if [ -n "$V4A2" ];then
for XML2 in $AUDEFXML; do
	sed -i "/<libraries>/a\        <library name=\"$LIBNAME2\" path=\"$LIB2\"\/>" $XML2
	sed -i "/<effects>/a\        <effect name=\"$NAME2\" library=\"$LIBNAME2\" uuid=\"$UUID2\"\ type=\"$TYPE2\"\/>" $XML2
done
fi